import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../../main.dart';
import '../../core/services/location_service.dart';
import '../../core/database/db_helper.dart';

class IssueReportScreen extends StatefulWidget {
  final String projectId;
  const IssueReportScreen({super.key, required this.projectId});

  @override
  State<IssueReportScreen> createState() => _IssueReportScreenState();
}

class _IssueReportScreenState extends State<IssueReportScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _severity = 'medium';
  File? _imageFile;
  Position? _currentPosition;
  bool _isSaving = false;
  bool _gpsLoading = false;

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (pickedFile != null) setState(() => _imageFile = File(pickedFile.path));
  }

  Future<void> _getLocation() async {
    setState(() => _gpsLoading = true);
    final pos = await LocationService.getCurrentLocation();
    setState(() {
      _currentPosition = pos;
      _gpsLoading = false;
    });
  }

  Future<void> _saveIssueLocally() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an issue title')),
      );
      return;
    }
    setState(() => _isSaving = true);
    final db = await DatabaseHelper.instance.database;
    final issueId = DateTime.now().millisecondsSinceEpoch.toString();
    await db.insert('issues', {
      'id': issueId,
      'project_id': widget.projectId,
      'title': _titleController.text,
      'description': _descController.text,
      'severity': _severity,
      'status': 'open',
      'location_lat': _currentPosition?.latitude,
      'location_lng': _currentPosition?.longitude,
      'sync_status': 'pending',
    });
    await db.insert('sync_queue', {
      'entity_type': 'issue',
      'entity_id': issueId,
      'operation': 'INSERT',
      'payload': jsonEncode({
        'id': issueId,
        'project_id': widget.projectId,
        'reported_by': Supabase.instance.client.auth.currentUser?.id,
        'title': _titleController.text,
        'description': _descController.text,
        'severity': _severity,
        'status': 'Open',
        'location_lat': _currentPosition?.latitude,
        'location_lng': _currentPosition?.longitude,
        'created_at': DateTime.now().toIso8601String(),
      }),
      'created_at': DateTime.now().toIso8601String(),
    });
    setState(() => _isSaving = false);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Report Issue'),
        backgroundColor: AppColors.danger,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Severity Selector ─────────────────────────────────────────
            _SectionTitle('Severity Level'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: ['low', 'medium', 'high', 'critical'].map((s) {
                  final isSelected = _severity == s;
                  Color c;
                  switch (s) {
                    case 'critical':
                      c = AppColors.danger;
                      break;
                    case 'high':
                      c = const Color(0xFFEA580C);
                      break;
                    case 'medium':
                      c = AppColors.amber;
                      break;
                    default:
                      c = AppColors.success;
                  }
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _severity = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? c : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          s[0].toUpperCase() + s.substring(1),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
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
            const SizedBox(height: 16),

            // ── Title & Description ───────────────────────────────────────
            _FormCard(
              child: TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Issue Title',
                  prefixIcon: Icon(Icons.title, color: AppColors.textSecondary),
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              child: TextField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.description_outlined, color: AppColors.textSecondary),
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Photo & GPS Row ────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.camera_alt_outlined,
                    label: _imageFile != null ? 'Photo Attached ✓' : 'Take Photo',
                    color: _imageFile != null ? AppColors.success : AppColors.blue,
                    onTap: _takePhoto,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: _gpsLoading ? Icons.hourglass_top : Icons.gps_fixed,
                    label: _currentPosition != null ? 'GPS Captured ✓' : 'Get GPS',
                    color: _currentPosition != null ? AppColors.success : const Color(0xFF8B5CF6),
                    onTap: _gpsLoading ? () {} : _getLocation,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Photo Preview ──────────────────────────────────────────────
            if (_imageFile != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Image.file(_imageFile!, width: double.infinity, height: 200, fit: BoxFit.cover),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => setState(() => _imageFile = null),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── GPS Card ───────────────────────────────────────────────────
            if (_currentPosition != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDDD6FE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFF8B5CF6), size: 20),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GPS Location Captured',
                            style: GoogleFonts.inter(
                                fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6D28D9))),
                        const SizedBox(height: 2),
                        Text(
                          '${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF7C3AED)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveIssueLocally,
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.upload_outlined),
                label: Text(
                  _isSaving ? 'Saving...' : 'Save Offline & Queue Sync',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
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
  const _FormCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
