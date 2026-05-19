import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';
import '../../core/database/db_helper.dart';
import 'issue_report_screen.dart';
import 'issue_discussion_screen.dart';

class IssuesListScreen extends StatefulWidget {
  const IssuesListScreen({super.key});

  @override
  State<IssuesListScreen> createState() => _IssuesListScreenState();
}

class _IssuesListScreenState extends State<IssuesListScreen> {
  List<Map<String, dynamic>> _issues = [];
  Map<String, String> _projectNames = {};
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIssues();
  }

  Future<void> _loadIssues() async {
    final db = await DatabaseHelper.instance.database;
    final issues = await db.query('issues', orderBy: 'created_at DESC');
    final projects = await db.query('projects', orderBy: 'name ASC');
    if (!mounted) return;
    setState(() {
      _issues = List<Map<String, dynamic>>.from(issues);
      _projects = List<Map<String, dynamic>>.from(projects);
      _projectNames = {
        for (final p in _projects) (p['id'] as String): (p['name'] as String? ?? '')
      };
      _loading = false;
    });
  }

  Future<void> _openReportFlow() async {
    if (_projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No projects loaded yet. Tap Sync on the Home screen and try again.',
          ),
        ),
      );
      return;
    }
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Which project is this issue about?',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _projects.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(_projects[i]['name'] as String? ?? ''),
              subtitle: Text(_projects[i]['district'] as String? ?? ''),
              onTap: () => Navigator.pop(ctx, _projects[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IssueReportScreen(projectId: picked['id'] as String),
      ),
    );
    // Refresh the list when the user comes back, in case they just filed one.
    if (mounted) _loadIssues();
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _severityColor(String? severity) {
    switch ((severity ?? '').toLowerCase()) {
      case 'critical':
      case 'high':
        return AppColors.danger;
      case 'medium':
        return AppColors.amber;
      default:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'My Reported Issues',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.blue,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _issues.isEmpty
              ? _EmptyState(onReport: _openReportFlow)
              : RefreshIndicator(
                  onRefresh: _loadIssues,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _issues.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final issue = _issues[i];
                      final id = issue['id'] as String;
                      final title = issue['title'] as String? ?? '(untitled)';
                      final projectId = issue['project_id'] as String? ?? '';
                      final projectName = _projectNames[projectId] ?? 'Unassigned project';
                      final severity = issue['severity'] as String? ?? 'low';
                      final syncStatus = issue['sync_status'] as String? ?? 'pending';
                      final createdAt = issue['created_at'] as String?;
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IssueDiscussionScreen(
                                issueId: id,
                                title: title,
                                project: projectName,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      projectName,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary,
                                        letterSpacing: 1.2,
                                      ).copyWith(height: 1),
                                    ),
                                  ),
                                  Text(
                                    _timeAgo(createdAt),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _severityColor(severity).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      severity.toUpperCase(),
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _severityColor(severity),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (syncStatus != 'synced')
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.amber.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.cloud_upload_outlined,
                                              size: 11, color: AppColors.amber),
                                          const SizedBox(width: 3),
                                          Text(
                                            'PENDING',
                                            style: GoogleFonts.inter(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.amber,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.danger,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Report Issue',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        onPressed: _openReportFlow,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onReport;
  const _EmptyState({required this.onReport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_outlined, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No issues reported yet',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the red button below to file your first issue.\n'
              'Reports save locally first and sync when online.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
