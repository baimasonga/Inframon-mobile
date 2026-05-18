import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../main.dart';
import '../../core/database/db_helper.dart';
import '../../core/services/location_service.dart';

class InspectionFormScreen extends StatefulWidget {
  final String projectId;
  const InspectionFormScreen({super.key, required this.projectId});

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  final _notesController = TextEditingController();
  final _inspectorNameController = TextEditingController();
  String? _inspectorId;
  File? _photo;
  bool _isSaving = false;
  double? _gpsLat;
  double? _gpsLng;
  bool _gpsLoading = false;
  
  double _overallProgress = 0;
  double _ppeCompliance = 80;
  String _visitType = 'Routine';
  String _weather = 'Clear / Sunny';

  final List<Map<String, dynamic>> _defects = [];

  final List<Map<String, dynamic>> _checklist = [
    {'task': 'Foundation/Structural Integrity', 'done': false, 'category': 'Structural'},
    {'task': 'Concrete Slump/Cube Tests', 'done': false, 'category': 'Materials'},
    {'task': 'Material Storage & Spoilage', 'done': false, 'category': 'Materials'},
    {'task': 'HSE Signage & Perimeter Scaffolding', 'done': false, 'category': 'HSE'},
    {'task': 'PPE Compliance (Helmet/Vests)', 'done': false, 'category': 'HSE'},
    {'task': 'Approved Plans on Site', 'done': false, 'category': 'Compliance'},
    {'task': 'Waste Disposal & Environment', 'done': false, 'category': 'HSE'},
  ];

  int get _doneCount => _checklist.where((i) => i['done'] == true).length;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final db = await DatabaseHelper.instance.database;
    final profile = await db.query('user_profile', limit: 1);
    if (profile.isNotEmpty) {
      setState(() {
        _inspectorId = profile.first['id'] as String;
        _inspectorNameController.text = profile.first['full_name'] as String;
      });
    }
  }

  Future<void> _captureGPS() async {
    setState(() => _gpsLoading = true);
    final result = await LocationService.getLocationWithFeedback();
    setState(() {
      _gpsLoading = false;
      if (result.hasLocation) {
        _gpsLat = result.position!.latitude;
        _gpsLng = result.position!.longitude;
      }
    });
    if (!result.hasLocation && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'GPS unavailable.'),
          backgroundColor: const Color(0xFFf59e0b),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  Future<void> _saveInspection() async {
    if (_inspectorNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter inspector name')));
      return;
    }

    setState(() => _isSaving = true);
    final db = await DatabaseHelper.instance.database;
    final visitId = 'vst-${DateTime.now().millisecondsSinceEpoch}';
    
    // 1. Persist Master Record locally
    await db.insert('visit_metadata', {
      'id': visitId,
      'project_id': widget.projectId,
      'inspector_id': _inspectorId ?? 'unknown',
      'date_time': DateTime.now().toIso8601String(),
      'visit_type': _visitType,
      'weather_condition': _weather,
      'site_supervisor_present': 1,
      'overall_progress': _overallProgress.toInt(),
      'overall_status': _overallProgress > 70 ? 'Good' : 'Fair',
      'notes': _notesController.text,
      'gps_lat': _gpsLat,
      'gps_lng': _gpsLng,
      'sync_status': 'pending',
    });

    // 2. Prepare payload for Transactional Sync (Framework RPC)
    final payload = {
      'project_id': widget.projectId,
      'inspector_id': _inspectorId ?? 'unknown',
      'date_time': DateTime.now().toIso8601String(),
      'visit_type': _visitType,
      'weather_condition': _weather,
      'site_supervisor_present': true,
      'overall_progress': _overallProgress.toInt(),
      'overall_status': _overallProgress > 70 ? 'Good' : 'Fair',
      'recommendation': _overallProgress > 70 ? 'Continue work' : 'Proceed with caution',
      'notes': _notesController.text,
      'milestones': [], 
      'issues': _defects,
      'quality_checks': _checklist.map((c) => {
        'check_item': c['task'],
        'category': c['category'],
        'pass': c['done'],
        'notes': ''
      }).toList(),
      'hse_record': {
        'ppe_usage_pct': _ppeCompliance.toInt(),
        'incident_reports': 'None',
        'waste_management': _checklist.any((c) => c['task'].contains('Waste') && c['done']) ? 'Verified' : 'Pending',
        'environmental_protection': 'Standard',
        'first_aid_available': true
      },
      'equipment': {
        'machinery_available': 'Site tools',
        'equipment_condition': 'Operational',
        'fuel_availability': 'Adequate'
      },
      'community': {
        'satisfaction_level': 'Satisfied',
        'complaints': _notesController.text.contains('complaint') ? _notesController.text : 'None',
        'land_disputes': false
      },
      'compliance': {
        'approved_drawings_on_site': _checklist.any((c) => c['category'] == 'Compliance' && c['done']),
        'work_permits_valid': true,
        'notes': 'Verified on-site'
      },
      'gps_lat': _gpsLat,
      'gps_lng': _gpsLng,
      'photos': _photo != null ? [
        {'url': 'https://placeholder.com/site.jpg', 'category': 'During', 'caption': 'Mobile Site Capture'}
      ] : []
    };

    // 3. Queue for Sync
    await db.insert('sync_queue', {
      'entity_type': 'field_report', // Triggers the RPC in SyncProvider
      'entity_id': visitId,
      'operation': 'INSERT',
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });

    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inspection saved to sync queue')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _doneCount / _checklist.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Inspection Form')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Progress Header ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.blue, Color(0xFF0A3260)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Checklist Progress',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$_doneCount',
                        style: GoogleFonts.inter(
                            fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white, height: 1)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(' / ${_checklist.length} items',
                          style: GoogleFonts.inter(fontSize: 16, color: Colors.white60)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress == 1.0 ? AppColors.success : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Metadata Card ───────────────────────────────────────────
          _FormCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                TextField(
                  controller: _inspectorNameController,
                  decoration: const InputDecoration(
                    labelText: 'Inspector Name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: InputBorder.none,
                    filled: false,
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _visitType,
                          isExpanded: true,
                          items: ['Routine', 'Follow-up', 'Final', 'Emergency']
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) => setState(() => _visitType = v!),
                        ),
                      ),
                    ),
                    const VerticalDivider(),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _weather,
                          isExpanded: true,
                          items: ['Clear / Sunny', 'Rainy', 'Cloudy', 'Harmattan']
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) => setState(() => _weather = v!),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Progress & Safety Sliders ─────────────────────────────────
          _SectionTitle('Progress & Safety'),
          const SizedBox(height: 8),
          _FormCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Overall Progress', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('${_overallProgress.toInt()}%', style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _overallProgress,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setState(() => _overallProgress = v),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('PPE Compliance', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('${_ppeCompliance.toInt()}%', style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _ppeCompliance,
                  max: 100,
                  divisions: 10,
                  onChanged: (v) => setState(() => _ppeCompliance = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SizedBox(height: 12),

          // ── Checklist ────────────────────────────────────────────────
          _SectionTitle('Safety Checklist'),
          const SizedBox(height: 8),
          _FormCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: _checklist.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                final isLast = i == _checklist.length - 1;
                return Column(
                  children: [
                    InkWell(
                      onTap: () => setState(() => item['done'] = !(item['done'] as bool)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: item['done'] == true ? AppColors.success : Colors.transparent,
                                border: Border.all(
                                  color: item['done'] == true ? AppColors.success : AppColors.border,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: item['done'] == true
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                item['task'],
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: item['done'] == true
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                  decoration: item['done'] == true
                                      ? TextDecoration.lineThrough
                                      : null,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast) const Divider(height: 1, indent: 52, color: AppColors.border),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // ── GPS Location ──────────────────────────────────────────────
          _SectionTitle('GPS Location'),
          const SizedBox(height: 8),
          _FormCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_gpsLat != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF16a34a), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lat: ${_gpsLat!.toStringAsFixed(6)}, Lng: ${_gpsLng!.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF16a34a), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'GPS not yet captured for this visit.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748b)),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _gpsLoading ? null : _captureGPS,
                    icon: _gpsLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 18),
                    label: Text(
                      _gpsLoading
                          ? 'Acquiring GPS…'
                          : _gpsLat != null
                              ? 'Recapture GPS'
                              : 'Capture GPS Location',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.blue,
                      side: const BorderSide(color: AppColors.blue),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Photo Capture ─────────────────────────────────────────────
          _SectionTitle('Inspection Photo'),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickPhoto,
            borderRadius: BorderRadius.circular(16),
            child: _photo != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        Image.file(_photo!, width: double.infinity, height: 200, fit: BoxFit.cover),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: _pickPhoto,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text('Retake', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 40, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text('Tap to take inspection photo',
                            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // ── Notes ─────────────────────────────────────────────────────
          _SectionTitle('Additional Notes'),
          const SizedBox(height: 8),
          _FormCard(
            child: TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add any additional observations or remarks...',
                border: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ── Submit ───────────────────────────────────────────────────
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveInspection,
              style: ElevatedButton.styleFrom(
                backgroundColor: _doneCount == _checklist.length ? AppColors.success : AppColors.blue,
              ),
              child: _isSaving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Text(
                      _doneCount == _checklist.length
                          ? 'Submit Complete Inspection ✓'
                          : 'Submit Inspection (Offline Ready)',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 32),
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
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}
