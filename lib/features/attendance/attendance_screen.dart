import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/location_service.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../core/database/db_helper.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _checkedIn = false;
  String? _checkInTime;
  bool _loading = false;
  String? _activeProjectId;
  String? _activeProjectName;

  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = await DatabaseHelper.instance.database;

    // Load local attendance records
    final records = await db.query(
      'attendance_records',
      orderBy: 'created_at DESC',
      limit: 20,
    );
    // Load today's check-in state
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayRecord = records.where((r) {
      final ci = r['check_in_time'] as String? ?? '';
      return ci.startsWith(today) && (r['check_out_time'] == null || r['check_out_time'] == '');
    }).toList();

    // Load projects for picker
    final projectRows = await db.query('projects', orderBy: 'name ASC');

    if (mounted) {
      setState(() {
        _logs = List<Map<String, dynamic>>.from(records);
        _projects = List<Map<String, dynamic>>.from(projectRows);
        if (todayRecord.isNotEmpty) {
          _checkedIn = true;
          final dt = DateTime.tryParse(todayRecord.first['check_in_time'] as String? ?? '');
          _checkInTime = dt != null ? DateFormat('HH:mm').format(dt) : null;
          _activeProjectId = todayRecord.first['project_id'] as String?;
        }
      });
    }
  }

  Future<void> _checkIn() async {
    if (_activeProjectId == null && _projects.isNotEmpty) {
      await _pickProject();
      if (_activeProjectId == null) return;
    }
    setState(() => _loading = true);

    // Get location with specific error feedback
    final locResult = await LocationService.getLocationWithFeedback();

    if (!locResult.hasLocation && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${locResult.errorMessage ?? 'GPS unavailable.'} '
            'Check-in saved without GPS verification.',
          ),
          backgroundColor: const Color(0xFFf59e0b),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }

    _doCheckIn(locResult.position?.latitude, locResult.position?.longitude);
  }

  Future<void> _pickProject() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select Project',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: _projects.isEmpty
              ? const Text('No projects loaded. Please sync first.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _projects.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(_projects[i]['name'] as String),
                    subtitle: Text(_projects[i]['district'] as String? ?? ''),
                    onTap: () => Navigator.pop(ctx, _projects[i]),
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _activeProjectId = picked['id'] as String;
        _activeProjectName = picked['name'] as String;
      });
    }
  }

  Future<void> _doCheckIn(double? lat, double? lng) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();
    final profileRows = await db.query('user_profile', limit: 1);
    final inspectorId = profileRows.isNotEmpty
        ? profileRows.first['id'] as String?
        : null;

    await db.insert('attendance_records', {
      'id': id,
      'project_id': _activeProjectId ?? '',
      'inspector_id': inspectorId ?? '',
      'check_in_time': now.toIso8601String(),
      'check_out_time': null,
      'total_hours': null,
      'gps_lat': lat,
      'gps_lng': lng,
      'verified_gps': lat != null ? 1 : 0,
      'sync_status': 'pending',
      'created_at': now.toIso8601String(),
    });

    if (mounted) {
      setState(() {
        _checkedIn = true;
        _checkInTime = DateFormat('HH:mm').format(now);
        _loading = false;
      });
    }
    await _loadData();
  }

  Future<void> _checkOut() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);

    final todayRecords = await db.query(
      'attendance_records',
      where: "check_in_time LIKE ? AND (check_out_time IS NULL OR check_out_time = '')",
      whereArgs: ['$today%'],
    );
    if (todayRecords.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final record = todayRecords.first;
    final checkInDt =
        DateTime.tryParse(record['check_in_time'] as String? ?? '') ?? now;
    final totalHours =
        now.difference(checkInDt).inMinutes / 60.0;

    await db.update(
      'attendance_records',
      {'check_out_time': now.toIso8601String(), 'total_hours': totalHours},
      where: 'id = ?',
      whereArgs: [record['id']],
    );

    // Queue for sync
    await db.insert('sync_queue', {
      'entity_type': 'attendance_log',
      'entity_id': record['id'],
      'operation': 'INSERT',
      'payload': jsonEncode({
        'id': record['id'],
        'project_id': record['project_id'],
        'inspector_id': record['inspector_id'],
        'check_in_time': record['check_in_time'],
        'check_out_time': now.toIso8601String(),
        'gps_lat': record['gps_lat'],
        'gps_lng': record['gps_lng'],
        'verified_gps': record['verified_gps'] == 1,
        'total_hours': double.parse(totalHours.toStringAsFixed(1)),
        'created_at': record['created_at'],
      }),
      'created_at': now.toIso8601String(),
    });

    if (mounted) {
      setState(() {
        _checkedIn = false;
        _loading = false;
        _activeProjectId = null;
        _activeProjectName = null;
      });
    }
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text('Time & Attendance',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Check-In / Out Card ───────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _checkedIn
                    ? const Color(0xFF0F172A)
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _checkedIn
                        ? Colors.transparent
                        : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Icon(
                    _checkedIn
                        ? Icons.location_on
                        : Icons.location_off_outlined,
                    size: 48,
                    color: _checkedIn
                        ? const Color(0xFF10B981)
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _checkedIn ? 'On Site' : 'Not Checked In',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _checkedIn ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  if (_checkedIn && _activeProjectName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _activeProjectName!,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: Colors.white60),
                    ),
                  ],
                  if (_checkedIn && _checkInTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Since $_checkInTime',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: Colors.white60),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading
                          ? null
                          : (_checkedIn ? _checkOut : _checkIn),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _checkedIn
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF1D6AE5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _checkedIn ? 'Check Out' : 'Check In',
                              style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            Text(
              'ATTENDANCE HISTORY',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),

            // ── Log List ─────────────────────────────────────────────────
            if (_logs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No attendance records yet.',
                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                  ),
                ),
              )
            else
              ..._logs.map((log) {
                final ci = DateTime.tryParse(
                    log['check_in_time'] as String? ?? '');
                final co = log['check_out_time'] != null
                    ? DateTime.tryParse(log['check_out_time'] as String)
                    : null;
                final verified = (log['verified_gps'] as int? ?? 0) == 1;
                final hours = (log['total_hours'] as num?)?.toDouble();

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            ci != null
                                ? DateFormat('MMM d, yyyy').format(ci)
                                : '—',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: const Color(0xFF0F172A)),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: verified
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              verified ? '✓ GPS Verified' : '⚠ Unverified',
                              style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: verified
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFFB45309)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _TimeChip(
                              label: 'In',
                              time: ci != null
                                  ? DateFormat('HH:mm').format(ci)
                                  : '—'),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward,
                              size: 14, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 8),
                          _TimeChip(
                              label: 'Out',
                              time: co != null
                                  ? DateFormat('HH:mm').format(co)
                                  : 'Pending'),
                          const Spacer(),
                          if (hours != null)
                            Text(
                              '${hours.toStringAsFixed(1)}h',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: const Color(0xFF3B82F6)),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label, time;
  const _TimeChip({required this.label, required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 9,
                  color: const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600)),
          Text(time,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A))),
        ],
      ),
    );
  }
}
