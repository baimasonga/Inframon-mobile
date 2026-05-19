import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';
import '../../core/database/db_helper.dart';

class WorkforceEntryScreen extends StatefulWidget {
  // projectId is optional now — the screen loads available projects from
  // the local sqflite cache and lets the inspector pick. Hardcoding a fake
  // id at the call site caused every save to fail the Supabase FK to
  // projects(id).
  final String? projectId;
  const WorkforceEntryScreen({super.key, this.projectId});

  @override
  State<WorkforceEntryScreen> createState() => _WorkforceEntryScreenState();
}

class _WorkforceEntryScreenState extends State<WorkforceEntryScreen> {
  final _countController = TextEditingController();
  String _role = 'laborer';
  String _gender = 'male';
  bool _isYouth = false;
  bool _isSaving = false;
  DateTime _selectedDate = DateTime.now();

  List<Map<String, dynamic>> _projects = [];
  String? _activeProjectId;
  String? _activeProjectName;

  @override
  void initState() {
    super.initState();
    _activeProjectId = widget.projectId;
    _loadProjects();
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('projects', orderBy: 'name ASC');
    if (!mounted) return;
    setState(() {
      _projects = List<Map<String, dynamic>>.from(rows);
      if (_activeProjectId != null) {
        final match = _projects.where((p) => p['id'] == _activeProjectId).toList();
        if (match.isNotEmpty) _activeProjectName = match.first['name'] as String?;
      }
    });
  }

  Future<void> _pickProject() async {
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
          'Select Project',
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
    if (picked != null && mounted) {
      setState(() {
        _activeProjectId = picked['id'] as String?;
        _activeProjectName = picked['name'] as String?;
      });
    }
  }

  void _resetForm() {
    _countController.clear();
    setState(() {
      _role = 'laborer';
      _gender = 'male';
      _isYouth = false;
      _selectedDate = DateTime.now();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.blue),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _saveEntry() async {
    if (_activeProjectId == null) {
      await _pickProject();
      if (!mounted) return;
      if (_activeProjectId == null) return;
    }
    final countText = _countController.text.trim();
    if (countText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the headcount')),
      );
      return;
    }
    final count = int.tryParse(countText);
    if (count == null || count < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Headcount must be a positive number')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final dateStr = _selectedDate.toIso8601String().split('T').first;
      await db.insert('workforce_records', {
        'id': id,
        'project_id': _activeProjectId,
        'record_date': dateStr,
        'role_category': _role,
        'gender': _gender,
        'is_youth': _isYouth ? 1 : 0,
        'count': count,
        'sync_status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('sync_queue', {
        'entity_type': 'workforce_record',
        'entity_id': id,
        'operation': 'INSERT',
        'payload': jsonEncode({
          'id': id,
          'project_id': _activeProjectId,
          'record_date': dateStr,
          'role_category': _role,
          'gender': _gender,
          'is_youth': _isYouth,
          'count': count,
          'created_at': DateTime.now().toIso8601String(),
        }),
        'created_at': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entry saved — $count $_role on $dateStr. Tap Sync on Home to send.',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _resetForm();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Log Daily Workforce'),
        backgroundColor: const Color(0xFF8B5CF6),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Project Picker ──────────────────────────────────────────
          _SectionTitle('Project'),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickProject,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_outlined,
                        color: Color(0xFF8B5CF6), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _activeProjectName == null ? 'Tap to choose' : 'Selected Project',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          _activeProjectName ?? 'No project selected',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _activeProjectName == null
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Date Picker ─────────────────────────────────────────────
          _SectionTitle('Work Date'),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_today, color: Color(0xFF8B5CF6), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selected Date',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
                      Text(
                        '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                        style: GoogleFonts.inter(
                            fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Role Category ────────────────────────────────────────────
          _SectionTitle('Job Role'),
          const SizedBox(height: 8),
          _FormCard(
            child: Column(
              children: [
                ['mason', 'Mason', Icons.construction],
                ['carpenter', 'Carpenter', Icons.carpenter],
                ['laborer', 'General Laborer', Icons.engineering],
                ['engineer', 'Engineer / Supervisor', Icons.manage_accounts],
              ].map((item) {
                final val = item[0] as String;
                final label = item[1] as String;
                final icon = item[2] as IconData;
                final isSelected = _role == val;
                return InkWell(
                  onTap: () => setState(() => _role = val),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(icon,
                            size: 20,
                            color: isSelected ? AppColors.blue : AppColors.textSecondary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(label,
                              style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? AppColors.blue : AppColors.textPrimary)),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle, color: AppColors.blue, size: 20),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // ── Gender & Youth ────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Gender'),
                    const SizedBox(height: 8),
                    _FormCard(
                      padding: const EdgeInsets.all(6),
                      child: Row(
                        children: ['male', 'female'].map((g) {
                          final isSelected = _gender == g;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _gender = g),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.blue : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  g[0].toUpperCase() + g.substring(1),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Youth'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Under 25',
                                style: GoogleFonts.inter(
                                    fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                          ),
                          Switch(
                            value: _isYouth,
                            onChanged: (v) => setState(() => _isYouth = v),
                            thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
                              if (states.contains(WidgetState.selected)) return AppColors.success;
                              return null;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Headcount ──────────────────────────────────────────────────
          _SectionTitle('Headcount'),
          const SizedBox(height: 8),
          _FormCard(
            child: TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: GoogleFonts.inter(fontSize: 22, color: AppColors.border),
                border: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 60),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Icon(Icons.people, color: AppColors.textSecondary, size: 24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ── Submit ─────────────────────────────────────────────────────
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveEntry,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              child: _isSaving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Text('Log Entry (Offline Ready)',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary));
  }
}

class _FormCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _FormCard({required this.child, this.padding});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}
