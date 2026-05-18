import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

class AIPhotoScreen extends StatefulWidget {
  const AIPhotoScreen({super.key});

  @override
  State<AIPhotoScreen> createState() => _AIPhotoScreenState();
}

class _AIPhotoScreenState extends State<AIPhotoScreen> {
  File? _selectedImage;
  bool _isAnalyzing = false;
  _AnalysisResult? _result;
  List<_AnalysisResult> _history = [];
  bool _isLoadingHistory = true;
  final _picker = ImagePicker();
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final data = await _supabase
          .from('analysis_results')
          .select('*, visit_metadata(date_time)')
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _history = data.map((item) {
            final payload = item['analysis_payload'] as Map<String, dynamic>;
            return _AnalysisResult(
              imageLabel: 'Site Capture — ${item['id'].toString().substring(0, 8)}',
              date: item['created_at'],
              progressScore: payload['progress_score'] ?? 0,
              qualityScore: payload['quality_score'] ?? 0,
              issues: List<String>.from(payload['findings'] ?? []),
            );
          }).toList();
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch AI history: $e');
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
        _result = null;
      });
    }
  }

  Future<void> _analyze() async {
    if (_selectedImage == null) return;
    setState(() => _isAnalyzing = true);
    
    // In a production flow, the analysis is triggered via the sync engine / database trigger.
    // Here we simulate the wait for the background server-side analysis to complete.
    await Future.delayed(const Duration(seconds: 3));
    
    // Refresh history to pick up the new result from the server
    await _fetchHistory();
    
    if (_history.isNotEmpty) {
      setState(() {
        _isAnalyzing = false;
        _result = _history.first;
      });
    } else {
      setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text('AI Photo Analysis', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Upload area
            GestureDetector(
              onTap: () => _showPickerSheet(),
              child: Container(
                width: double.infinity,
                height: _selectedImage != null ? 220 : 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
                ),
                child: _selectedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(_selectedImage!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt_outlined, size: 28, color: Color(0xFF3B82F6)),
                          ),
                          const SizedBox(height: 12),
                          Text('Tap to capture or select site photo', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                        ],
                      ),
              ),
            ),

            if (_selectedImage != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showPickerSheet(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text('Change Photo', style: GoogleFonts.inter(fontSize: 13)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzing ? null : _analyze,
                      icon: _isAnalyzing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_awesome, size: 16),
                      label: Text(_isAnalyzing ? 'Analyzing…' : 'Analyze Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Result card
            if (_result != null) ...[
              const SizedBox(height: 20),
              _buildResultCard(_result!),
            ],

            // History
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Analysis History', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: const Color(0xFF0F172A))),
                if (_isLoadingHistory) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            if (!_isLoadingHistory && _history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No analysis results found.', style: GoogleFonts.inter(color: Colors.grey))),
              ),
            ..._history.map((r) => _buildHistoryCard(r)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(_AnalysisResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('AI Analysis Result', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
          ]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _ScoreWidget(label: 'Progress Score', score: result.progressScore)),
              const SizedBox(width: 16),
              Expanded(child: _ScoreWidget(label: 'Quality Score', score: result.qualityScore)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Findings', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 8),
          ...result.issues.map((i) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.circle, size: 6, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(child: Text(i, style: GoogleFonts.inter(fontSize: 13, color: Colors.white))),
            ]),
          )),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(_AnalysisResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.image_outlined, color: Color(0xFF3B82F6)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(result.imageLabel, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF0F172A))),
            Text(result.date, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
          ])),
          Column(children: [
            Text('${result.progressScore}%', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF3B82F6))),
            Text('progress', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
          ]),
        ],
      ),
    );
  }

  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt), title: Text('Take Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); }),
          ListTile(leading: const Icon(Icons.photo_library), title: Text('Choose from Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); }),
        ]),
      ),
    );
  }
}

class _ScoreWidget extends StatelessWidget {
  final String label;
  final int score;
  const _ScoreWidget({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text('$score%', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 22, color: Colors.white)),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.white70), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _AnalysisResult {
  final String imageLabel, date;
  final int progressScore, qualityScore;
  final List<String> issues;
  const _AnalysisResult({required this.imageLabel, required this.date, required this.progressScore, required this.qualityScore, required this.issues});
}
