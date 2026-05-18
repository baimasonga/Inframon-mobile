import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  String _selectedProject = 'Freetown Ring Road';
  final _projects = ['Freetown Ring Road', 'Bo-Kenema Highway', 'Kenema Solar Well', 'Bonthe Bridge'];
  
  File? _verificationImage;
  final _picker = ImagePicker();
  bool _isSubmitting = false;

  final _notesController = TextEditingController();
  final double _reportedProgress = 65.0; // What the clerk reported
  double _verifiedProgress = 65.0; // What the engineer is overriding it to
  bool _flagAsIssue = false;

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) {
      setState(() => _verificationImage = File(picked.path));
    }
  }

  Future<void> _submitVerification() async {
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Field Verification Saved!', style: GoogleFonts.inter()),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Engineer Verification', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project Selector
            Text('Target Project', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF64748B))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedProject,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF94A3B8)),
                  onChanged: (v) => setState(() => _selectedProject = v!),
                  items: _projects.map((p) => DropdownMenuItem(value: p, child: Text(p, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))))).toList(),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Progress Override Module
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 8),
                    Text('Progress Audit', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                  ]),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Clerk Reported', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                        Text('${_reportedProgress.toInt()}%', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 24, color: Colors.white)),
                      ]),
                      const Icon(Icons.arrow_forward, color: Colors.white30),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('Engineer Verified', style: GoogleFonts.inter(fontSize: 12, color: Colors.blueAccent)),
                        Text('${_verifiedProgress.toInt()}%', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 24, color: Colors.blueAccent)),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.blueAccent,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                      overlayColor: Colors.blueAccent.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _verifiedProgress,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      onChanged: (v) => setState(() => _verifiedProgress = v),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Independent Photo Verification
            Text('Independent Field Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF64748B))),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: _verificationImage != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(_verificationImage!, fit: BoxFit.cover)),
                          Positioned(
                            bottom: 10, right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.gps_fixed, color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text('Verified GPS Match', style: GoogleFonts.inter(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          )
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt, color: Color(0xFF3B82F6), size: 28),
                          ),
                          const SizedBox(height: 12),
                          Text('Capture Proof of Override', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                          Text('Required if overriding Clerk progress', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // Corrective Notes
            Text('Corrective Actions / Notes', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF64748B))),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _notesController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Describe material discrepancies, structural flaws, or required rework...',
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  CheckboxListTile(
                    value: _flagAsIssue,
                    onChanged: (v) => setState(() => _flagAsIssue = v ?? false),
                    title: Text('Escalate to Risk Register', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626))),
                    subtitle: Text('Flags this project on the web dashboard immediately', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                    activeColor: const Color(0xFFDC2626),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  )
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitVerification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Submit Field Verification', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
