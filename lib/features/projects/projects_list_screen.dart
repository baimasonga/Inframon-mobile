import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../core/database/db_helper.dart';
import '../inspections/multi_step_wizard.dart';
import '../issues/issue_report_screen.dart';
import 'timeline_screen.dart';
import 'map_screen.dart';

class ProjectsListScreen extends StatefulWidget {
  const ProjectsListScreen({super.key});

  @override
  State<ProjectsListScreen> createState() => _ProjectsListScreenState();
}

class _ProjectsListScreenState extends State<ProjectsListScreen> {
  List<Map<String, dynamic>> _projects = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchProjects();
  }

  Future<void> _fetchProjects() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final localProjects = await db.query('projects', orderBy: 'created_at DESC');

      if (localProjects.isNotEmpty) {
        final mapped = localProjects.map((p) {
          final pct = (p['completion_percentage'] as int? ?? 0) / 100.0;
          return {
            'id': p['id'],
            'name': p['name'],
            'status': (p['status'] ?? '').toString().toLowerCase(),
            'phase': p['status'] == 'Completed'
                ? 'Completed'
                : 'Phase: Tracking',
            'progress': pct.clamp(0.0, 1.0),
            'inspections': 0,
            'issues': 0,
            'location': p['district'] ?? 'Sierra Leone',
          };
        }).toList();

        if (mounted) {
          setState(() {
            _projects = List<Map<String, dynamic>>.from(mapped);
            _isLoading = false;
          });
        }
        return;
      }

      // Online fallback on first run (before sync)
      final data = await Supabase.instance.client
          .from('projects')
          .select()
          .order('created_at', ascending: false);

      final mapped = (data as List<dynamic>).map((p) {
        final pct = ((p['completion_percentage'] ?? 0) as num) / 100.0;
        return {
          'id': p['id'],
          'name': p['name'],
          'status': (p['status'] ?? '').toString().toLowerCase(),
          'phase': p['status'] == 'Completed' ? 'Completed' : 'Phase: Active',
          'progress': pct.clamp(0.0, 1.0),
          'inspections': 0,
          'issues': 0,
          'location': p['district'] ?? 'Sierra Leone',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _projects = List<Map<String, dynamic>>.from(mapped);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching projects: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _projects;
    final q = _searchQuery.toLowerCase();
    return _projects.where((p) {
      return (p['name'] as String).toLowerCase().contains(q) ||
          (p['location'] as String).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MapScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProjects,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search projects...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_open,
                                size: 48, color: AppColors.border),
                            const SizedBox(height: 12),
                            Text(
                              _projects.isEmpty
                                  ? 'No projects yet.\nTap Sync on the home screen to load your assignments.'
                                  : 'No projects match "$_searchQuery"',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchProjects,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) =>
                              _ProjectCard(p: _filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatefulWidget {
  final Map<String, dynamic> p;
  const _ProjectCard({required this.p});

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final double progress = (p['progress'] as double).clamp(0.0, 1.0);
    final bool isActive = p['status'] == 'active';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.blueSoft
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isActive ? 'Active' : p['status'].toString(),
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? AppColors.blue
                                  : AppColors.textSecondary),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p['name'],
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(p['location'],
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['phase'],
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 8,
                                backgroundColor: AppColors.blueSoft,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isActive
                                      ? AppColors.blue
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${(progress * 100).round()}%',
                        style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  _ActionTile(
                    icon: Icons.fact_check,
                    label: 'New Site Inspection Report',
                    iconColor: AppColors.blue,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MultiStepInspectionWizard(
                          projectId: p['id'],
                          projectName: p['name'],
                          projectType: p['phase'],
                        ),
                      ),
                    ),
                  ),
                  _ActionTile(
                    icon: Icons.report_problem,
                    label: 'Report Issue',
                    iconColor: AppColors.danger,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            IssueReportScreen(projectId: p['id']),
                      ),
                    ),
                  ),
                  _ActionTile(
                    icon: Icons.timeline,
                    label: 'View Timeline',
                    iconColor: AppColors.success,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TimelineScreen(projectId: p['id']),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}



class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const Spacer(),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
