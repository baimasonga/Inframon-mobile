import 'dart:io';
  import 'dart:convert';
  import 'package:flutter/material.dart';
  import 'package:google_fonts/google_fonts.dart';
  import 'package:image_picker/image_picker.dart';
  import 'package:geolocator/geolocator.dart';
  import 'package:provider/provider.dart';
  import '../../main.dart';
  import '../../core/database/db_helper.dart';
  import '../sync/sync_provider.dart';
  import '../inspections/multi_step_wizard.dart';

  class TaskDetailScreen extends StatefulWidget {
    final Map<String, dynamic> task;
    const TaskDetailScreen({super.key, required this.task});

    @override
    State<TaskDetailScreen> createState() => _TaskDetailScreenState();
  }

  class _TaskDetailScreenState extends State<TaskDetailScreen> {
    late String _status;
    final _notesController = TextEditingController();
    File? _photo;
    double? _gpsLat;
    double? _gpsLng;
    bool _isSaving = false;
    bool _isCapturingGps = false;
    String? _projectName;
    String _projectType = 'Infrastructure Project';

    @override
    void initState() {
      super.initState();
      _status = widget.task['status'] ?? 'Pending';
      _notesController.text = widget.task['field_notes'] as String? ?? '';
      if (widget.task['gps_lat'] != null) {
        _gpsLat = (widget.task['gps_lat'] as num).toDouble();
        _gpsLng = (widget.task['gps_lng'] as num?)?.toDouble();
      }
      _loadProjectName();
    }

    @override
    void dispose() {
      _notesController.dispose();
      super.dispose();
    }

    Future<void> _loadProjectName() async {
      final projectId = widget.task['project_id'];
      if (projectId == null) return;
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('projects',
          where: 'id = ?', whereArgs: [projectId], limit: 1);
      if (rows.isNotEmpty && mounted) {
        final row = rows.first;
        setState(() {
          _projectName = row['name'] as String?;
          final desc = (row['description'] as String? ?? '').toLowerCase();
          if (desc.contains('road') || desc.contains('feeder')) {
            _projectType = 'Feeder Road';
          } else if (desc.contains('school') || desc.contains('education')) {
            _projectType = 'School Building';
          } else if (desc.contains('health') || desc.contains('clinic')) {
            _projectType = 'Health Facility';
          } else if (desc.contains('bridge')) {
            _projectType = 'Bridge';
          } else if (desc.contains('water') || desc.contains('borehole')) {
            _projectType = 'Water & Sanitation';
          }
        });
      }
    }

    Future<void> _launchInspection() async {
      final projectId = widget.task['project_id'] as String?;
      if (projectId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No project linked to this task')),
        );
        return;
      }
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => MultiStepInspectionWizard(
            projectId: projectId,
            projectName: _projectName ?? 'Project Inspection',
            projectType: _projectType,
            taskId: widget.task['id'] as String,
          ),
        ),
      );
      if (result == 'task_completed' && mounted) {
        Navigator.pop(context, true);
      }
    }

    Future<void> _captureGps() async {
      setState(() => _isCapturingGps = true);
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) throw Exception('Location services are disabled');

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            throw Exception('Location permission denied');
          }
        }
        if (permission == LocationPermission.deniedForever) {
          throw Exception('Location permissions permanently denied');
        }

        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        if (mounted) {
          setState(() {
            _gpsLat = pos.latitude;
            _gpsLng = pos.longitude;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('GPS error: $e'), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) setState(() => _isCapturingGps = false);
      }
    }

    Future<void> _pickPhoto() async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.camera, imageQuality: 75);
      if (picked != null && mounted) {
        setState(() => _photo = File(picked.path));
      }
    }

    Future<void> _saveUpdate() async {
      setState(() => _isSaving = true);
      try {
        final db = await DatabaseHelper.instance.database;
        final taskId = widget.task['id'] as String;
        final now = DateTime.now().toIso8601String();
        final notes = _notesController.text.trim();

        // 1. Update local SQLite
        await db.update(
          'inspection_tasks',
          {
            'status': _status,
            'field_notes': notes.isEmpty ? null : notes,
            'gps_lat': _gpsLat,
            'gps_lng': _gpsLng,
            'updated_at': now,
            'sync_status': 'pending',
          },
          where: 'id = ?',
          whereArgs: [taskId],
        );

        // 2. Enqueue upstream sync
        final payload = jsonEncode({
          'id': taskId,
          'status': _status,
          'updated_at': now,
          if (_gpsLat != null) 'gps_lat': _gpsLat,
          if (_gpsLng != null) 'gps_lng': _gpsLng,
        });
        await db.insert('sync_queue', {
          'entity_type': 'inspection_task_update',
          'entity_id': taskId,
          'operation': 'UPDATE',
          'payload': payload,
          'created_at': now,
        });

        if (mounted) {
          // Trigger background sync
          context.read<SyncProvider>().syncNow();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Task updated — syncing to server'),
            backgroundColor: Color(0xFF10B981),
          ));
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }

    Color _priorityColor(String priority) {
      switch (priority) {
        case 'Urgent':  return Colors.deepPurple;
        case 'High':    return AppColors.danger;
        case 'Low':     return Colors.teal;
        default:        return AppColors.amber;
      }
    }

    @override
    Widget build(BuildContext context) {
      final priority = widget.task['priority'] as String? ?? 'Normal';
      final deadline = widget.task['deadline'] as String?;
      final pc = _priorityColor(priority);

      bool isOverdue = false;
      if (deadline != null) {
        try {
          isOverdue = DateTime.parse(deadline).isBefore(DateTime.now()) &&
              _status != 'Completed';
        } catch (_) {}
      }

      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Task Details'),
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header badges ──────────────────────────────────────────────
              Row(
                children: [
                  _badge(priority, pc),
                  if (isOverdue) ...[
                    const SizedBox(width: 8),
                    _badge('OVERDUE', AppColors.danger),
                  ],
                ],
              ),
              const SizedBox(height: 14),

              // ── Title ──────────────────────────────────────────────────────
              Text(
                widget.task['title'] as String? ?? 'Untitled Task',
                style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),

              // ── Project + Deadline ─────────────────────────────────────────
              if (_projectName != null) ...[
                const SizedBox(height: 6),
                _metaRow(Icons.business, _projectName!, AppColors.textSecondary),
              ],
              if (deadline != null) ...[
                const SizedBox(height: 4),
                _metaRow(Icons.calendar_today, 'Deadline: $deadline',
                    isOverdue ? AppColors.danger : AppColors.textSecondary),
              ],

              // ── Description ────────────────────────────────────────────────
              if ((widget.task['description'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    widget.task['description'] as String,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.6),
                  ),
                ),
              ],

              const SizedBox(height: 28),
              _sectionLabel('Update Status'),
              const SizedBox(height: 10),

              // ── Status selector ────────────────────────────────────────────
              Row(
                children: _statusOptions.map((opt) {
                  final sel = _status == opt['label'];
                  final col = opt['color'] as Color;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _status = opt['label'] as String),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: sel ? col.withValues(alpha: 0.12) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: sel ? col : const Color(0xFFE2E8F0),
                              width: sel ? 2 : 1),
                        ),
                        child: Column(
                          children: [
                            Icon(opt['icon'] as IconData,
                                size: 22, color: sel ? col : AppColors.textSecondary),
                            const SizedBox(height: 4),
                            Text(
                              opt['short'] as String,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                                  color: sel ? col : AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 28),
              _sectionLabel('Field Notes'),
              const SizedBox(height: 8),

              // ── Notes input ────────────────────────────────────────────────
              TextFormField(
                controller: _notesController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Enter site observations, findings, or follow-up actions…',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(14),
                ),
                style: GoogleFonts.inter(fontSize: 14),
              ),

              const SizedBox(height: 28),
              _sectionLabel('GPS Location'),
              const SizedBox(height: 8),

              // ── GPS display ────────────────────────────────────────────────
              if (_gpsLat != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Color(0xFF10B981), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${_gpsLat!.toStringAsFixed(6)}, ${_gpsLng!.toStringAsFixed(6)}',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF10B981),
                            fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Icon(Icons.check_circle,
                          color: const Color(0xFF10B981), size: 16),
                    ],
                  ),
                ),

              OutlinedButton.icon(
                onPressed: _isCapturingGps ? null : _captureGps,
                icon: _isCapturingGps
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
                label: Text(_gpsLat != null
                    ? 'Update GPS Location'
                    : 'Capture GPS Location'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),

              const SizedBox(height: 28),
              _sectionLabel('Site Photo'),
              const SizedBox(height: 8),

              // ── Photo preview ──────────────────────────────────────────────
              if (_photo != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(_photo!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover),
                ),
                const SizedBox(height: 8),
              ],

              OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.camera_alt),
                label: Text(_photo != null ? 'Retake Photo' : 'Take Site Photo'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),

              const SizedBox(height: 36),

              // ── Save status update button ───────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Text('Save & Sync Update',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 12),

              // ── Start Full Inspection divider ───────────────────────────────
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),

              // ── Launch inspection wizard button ─────────────────────────────
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D6AE5), Color(0xFF0A3260)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1D6AE5).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.task['project_id'] == null ? null : _launchInspection,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.assignment_add, color: Colors.white, size: 22),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Start Full Site Inspection',
                                style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                              Text(
                                'Opens 7-step wizard — auto-completes this task',
                                style: GoogleFonts.inter(
                                    color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                          const Spacer(),
                          const Icon(Icons.chevron_right, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    }

    static const _statusOptions = [
      {'label': 'Pending',     'short': 'Pending',      'icon': Icons.radio_button_unchecked, 'color': Color(0xFF94A3B8)},
      {'label': 'In Progress', 'short': 'In\nProgress', 'icon': Icons.pending_actions,        'color': Color(0xFFF59E0B)},
      {'label': 'Completed',   'short': 'Done',          'icon': Icons.check_circle,            'color': Color(0xFF10B981)},
    ];

    Widget _badge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text,
          style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );

    Widget _metaRow(IconData icon, String text, Color color) => Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(child: Text(text, style: GoogleFonts.inter(fontSize: 13, color: color))),
      ],
    );

    Widget _sectionLabel(String text) => Text(text,
        style: GoogleFonts.inter(
            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
  }
  