import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TimelineScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  const TimelineScreen({super.key, required this.projectId, this.projectName = 'Project'});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<Map<String, dynamic>> _milestones = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMilestones();
  }

  Future<void> _loadMilestones() async {
    setState(() { _loading = true; _error = null; });
    try {
      final defs = await Supabase.instance.client
          .from('milestone_definitions')
          .select('id, milestone_name, planned_completion_date, sort_order')
          .eq('project_id', widget.projectId)
          .order('sort_order', ascending: true);

      final List<Map<String, dynamic>> enriched = [];
      for (final def in (defs as List<dynamic>)) {
        final logs = await Supabase.instance.client
            .from('milestone_logs')
            .select('status, completion_pct, date_achieved, delay_days, delay_reason')
            .eq('milestone_id', def['id'])
            .order('created_at', ascending: false)
            .limit(1);

        final log       = (logs as List<dynamic>).isNotEmpty ? logs.first : null;
        final status    = (log?['status']         as String?) ?? 'Not Started';
        final pct       = (log?['completion_pct'] as num?)?.toInt() ?? 0;
        final delayDays = (log?['delay_days']      as num?)?.toInt() ?? 0;
        final planned   = def['planned_completion_date'] as String?;
        final isOverdue = planned != null && status != 'Completed'
            && DateTime.tryParse(planned) != null
            && DateTime.parse(planned).isBefore(DateTime.now());

        enriched.add({
          'id':          def['id'],
          'name':        def['milestone_name'] ?? '—',
          'planned':     planned,
          'achieved':    log?['date_achieved'] as String?,
          'status':      status,
          'pct':         pct,
          'delayDays':   delayDays,
          'delayReason': log?['delay_reason'] as String?,
          'isOverdue':   isOverdue,
        });
      }
      if (mounted) setState(() { _milestones = enriched; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Color _statusColor(String status, bool overdue) {
    if (status == 'Completed')   return const Color(0xFF10b981);
    if (overdue)                 return const Color(0xFFef4444);
    if (status == 'In Progress') return const Color(0xFF3b82f6);
    return const Color(0xFF94a3b8);
  }

  IconData _statusIcon(String status, bool overdue) {
    if (status == 'Completed')   return Icons.check_circle_rounded;
    if (overdue)                 return Icons.error_rounded;
    if (status == 'In Progress') return Icons.timelapse_rounded;
    return Icons.radio_button_unchecked;
  }

  String _fmtDate(String? d) {
    if (d == null) return '—';
    final dt = DateTime.tryParse(d);
    if (dt == null) return d;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final completed   = _milestones.where((m) => m['status'] == 'Completed').length;
    final total       = _milestones.length;
    final overallPct  = total > 0
        ? (_milestones.fold<int>(0, (s, m) => s + (m['pct'] as int)) / total).round()
        : 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(widget.projectName,
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1e293b),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFe2e8f0)),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadMilestones, tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFcbd5e1)),
                  const SizedBox(height: 12),
                  Text('Could not load milestones', style: GoogleFonts.inter(color: const Color(0xFF64748b))),
                  TextButton(onPressed: _loadMilestones, child: const Text('Retry')),
                ]))
              : _milestones.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.flag_outlined, size: 56, color: Color(0xFFcbd5e1)),
                      const SizedBox(height: 12),
                      Text('No milestones defined', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748b))),
                      const SizedBox(height: 4),
                      Text('Add milestone definitions via the web dashboard.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94a3b8))),
                    ]))
                  : CustomScrollView(slivers: [
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF1e293b), Color(0xFF334155)]),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('MILESTONE PROGRESS', style: GoogleFonts.inter(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                            const SizedBox(height: 8),
                            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('$overallPct%', style: GoogleFonts.inter(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
                              const SizedBox(width: 12),
                              Padding(padding: const EdgeInsets.only(bottom: 6),
                                  child: Text('$completed / $total complete', style: GoogleFonts.inter(color: Colors.white60, fontSize: 13))),
                            ]),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: total > 0 ? overallPct / 100 : 0,
                                backgroundColor: Colors.white.withOpacity(0.15),
                                valueColor: const AlwaysStoppedAnimation(Color(0xFF10b981)),
                                minHeight: 8,
                              ),
                            ),
                          ]),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList(delegate: SliverChildBuilderDelegate((ctx, i) {
                          final m       = _milestones[i];
                          final status  = m['status'] as String;
                          final overdue = m['isOverdue'] as bool;
                          final pct     = m['pct'] as int;
                          final color   = _statusColor(status, overdue);
                          final isLast  = i == _milestones.length - 1;
                          return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            SizedBox(width: 44, child: Column(children: [
                              Container(width: 36, height: 36,
                                decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
                                child: Icon(_statusIcon(status, overdue), color: color, size: 18)),
                              if (!isLast) Expanded(child: Container(width: 2,
                                color: status == 'Completed' ? const Color(0xFF10b981).withOpacity(0.3) : const Color(0xFFe2e8f0))),
                            ])),
                            const SizedBox(width: 8),
                            Expanded(child: Container(
                              margin: EdgeInsets.only(bottom: isLast ? 16 : 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: overdue ? const Color(0xFFfecaca) : const Color(0xFFe2e8f0)),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text('${i + 1}. ${m['name']}',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF0f172a)))),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                                    child: Text(overdue ? 'Overdue' : status, style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                                  ),
                                ]),
                                const SizedBox(height: 10),
                                ClipRRect(borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(value: pct / 100,
                                    backgroundColor: const Color(0xFFf1f5f9),
                                    valueColor: AlwaysStoppedAnimation(color), minHeight: 6)),
                                const SizedBox(height: 4),
                                Align(alignment: Alignment.centerRight,
                                  child: Text('$pct%', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color))),
                                const SizedBox(height: 8),
                                if (m['planned'] != null)
                                  Text('Planned: ${_fmtDate(m['planned'] as String?)}',
                                      style: GoogleFonts.inter(fontSize: 11, color: overdue ? const Color(0xFFef4444) : const Color(0xFF64748b))),
                                if (m['achieved'] != null)
                                  Text('Achieved: ${_fmtDate(m['achieved'] as String?)}',
                                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF10b981), fontWeight: FontWeight.w600)),
                                if ((m['delayDays'] as int) > 0) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFFfef2f2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFfecaca))),
                                    child: Row(children: [
                                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFef4444), size: 14),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text('Delayed ${m['delayDays']}d${m['delayReason'] != null ? ": ${m['delayReason']}" : ""}',
                                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFb91c1c)))),
                                    ]),
                                  ),
                                ],
                              ]),
                            )),
                          ]));
                        }, childCount: _milestones.length)),
                      ),
                    ]),
    );
  }
}
