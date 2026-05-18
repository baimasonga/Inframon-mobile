import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../sync/sync_provider.dart';

enum _AlertType { task, milestone, inspection, risk, update }

class _Alert {
  final _AlertType type;
  final String title;
  final String body;
  final String time;
  final DateTime createdAt;
  final bool read;
  const _Alert({required this.type, required this.title, required this.body, required this.time, required this.createdAt, this.read = false});
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_Alert> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SyncProvider>().markTasksRead();
    });
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)   return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    if (diff.inDays < 7)      return '${diff.inDays}d ago';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month-1]}';
  }

  static String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month-1]} ${dt.year}';
  }

  static String _humanizeAction(String action) {
    final parts = action.replaceAll('_', ' ').split(' ');
    return parts.map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final List<_Alert> alerts = [];

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) { if (mounted) setState(() => _isLoading = false); return; }

      // ── 1. Task assignment notifications ──────────────────────────────────
      try {
        final tasks = await Supabase.instance.client
            .from('inspection_tasks')
            .select('id, title, description, priority, deadline, status, created_at')
            .eq('assignee_id', userId)
            .order('created_at', ascending: false)
            .limit(15);

        for (final t in tasks as List<dynamic>) {
          final createdAt = DateTime.tryParse(t['created_at'] as String? ?? '') ?? DateTime.now();
          final priority  = t['priority'] as String? ?? 'Normal';
          final deadline  = t['deadline'] != null ? DateTime.tryParse(t['deadline'] as String) : null;
          final isOverdue = deadline != null && deadline.isBefore(DateTime.now()) && t['status'] != 'Completed';
          alerts.add(_Alert(
            type: _AlertType.task,
            title: 'Task Assigned: ${t['title'] ?? 'Inspection Task'}',
            body: '$priority priority${deadline != null ? " — due ${_formatDate(deadline)}" : ""}${isOverdue ? " ⚠ Overdue!" : ""}',
            time: _timeAgo(createdAt), createdAt: createdAt,
            read: t['status'] != 'Pending',
          ));
        }
      } catch (e) { debugPrint('Task notifications error: $e'); }

      // ── 2. Milestone deadline alerts ──────────────────────────────────────
      try {
        final now = DateTime.now();
        final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
        final in7 = now.add(const Duration(days: 7));
        final in7Str  = '${in7.year}-${in7.month.toString().padLeft(2,'0')}-${in7.day.toString().padLeft(2,'0')}';

        // Overdue milestones
        final overdueMilestones = await Supabase.instance.client
            .from('milestone_definitions')
            .select('id, milestone_name, planned_completion_date, projects(name)')
            .lt('planned_completion_date', todayStr)
            .not('planned_completion_date', 'is', null);

        for (final m in overdueMilestones as List<dynamic>) {
          final mId = m['id']?.toString() ?? '';
          // Check latest log status
          final logs = await Supabase.instance.client
              .from('milestone_logs')
              .select('status')
              .eq('milestone_id', mId)
              .order('created_at', ascending: false)
              .limit(1);
          final latestStatus = (logs as List<dynamic>).isNotEmpty ? (logs.first['status'] as String?) ?? 'Not Started' : 'Not Started';
          if (latestStatus == 'Completed') continue;

          final planned = DateTime.tryParse(m['planned_completion_date'] as String? ?? '');
          if (planned == null) continue;
          final daysOverdue = now.difference(planned).inDays;
          final projectName = (m['projects'] as Map?)?['name'] as String? ?? 'Unknown Project';

          alerts.add(_Alert(
            type: _AlertType.milestone,
            title: 'Overdue Milestone: ${m['milestone_name']}',
            body: '$projectName — planned ${_formatDate(planned)}, now $daysOverdue day${daysOverdue != 1 ? "s" : ""} overdue.',
            time: 'Overdue', createdAt: planned, read: false,
          ));
        }

        // Due within 7 days
        final dueSoon = await Supabase.instance.client
            .from('milestone_definitions')
            .select('id, milestone_name, planned_completion_date, projects(name)')
            .gte('planned_completion_date', todayStr)
            .lte('planned_completion_date', in7Str)
            .not('planned_completion_date', 'is', null);

        for (final m in dueSoon as List<dynamic>) {
          final mId = m['id']?.toString() ?? '';
          final logs = await Supabase.instance.client
              .from('milestone_logs')
              .select('status')
              .eq('milestone_id', mId)
              .order('created_at', ascending: false)
              .limit(1);
          final latestStatus = (logs as List<dynamic>).isNotEmpty ? (logs.first['status'] as String?) ?? 'Not Started' : 'Not Started';
          if (latestStatus == 'Completed') continue;

          final planned = DateTime.tryParse(m['planned_completion_date'] as String? ?? '');
          if (planned == null) continue;
          final daysLeft = planned.difference(now).inDays;
          final projectName = (m['projects'] as Map?)?['name'] as String? ?? 'Unknown Project';

          alerts.add(_Alert(
            type: _AlertType.milestone,
            title: 'Milestone Due Soon: ${m['milestone_name']}',
            body: '$projectName — due ${_formatDate(planned)} ($daysLeft day${daysLeft != 1 ? "s" : ""} remaining).',
            time: '${daysLeft}d remaining', createdAt: planned, read: false,
          ));
        }
      } catch (e) { debugPrint('Milestone deadline alerts error: $e'); }

      // ── 3. Audit log notifications ─────────────────────────────────────────
      try {
        final data = await Supabase.instance.client
            .from('audit_logs')
            .select()
            .or('user_id.eq.$userId,target_id.eq.$userId')
            .order('created_at', ascending: false)
            .limit(20);

        for (final row in data as List<dynamic>) {
          final action = (row['action'] as String? ?? '').toLowerCase();
          _AlertType type;
          if (action.contains('inspection') || action.contains('task'))      type = _AlertType.inspection;
          else if (action.contains('risk') || action.contains('issue'))      type = _AlertType.risk;
          else                                                               type = _AlertType.update;
          final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
          alerts.add(_Alert(
            type: type,
            title: _humanizeAction(row['action'] as String? ?? ''),
            body: row['details'] as String? ?? row['description'] as String? ?? 'No details provided.',
            time: _timeAgo(createdAt), createdAt: createdAt, read: true,
          ));
        }
      } catch (e) { debugPrint('Audit notifications error: $e'); }

    } catch (e) { debugPrint('Notifications load error: $e'); }

    // Sort: overdue first, then by date descending
    alerts.sort((a, b) {
      final aOverdue = a.time == 'Overdue' ? 0 : 1;
      final bOverdue = b.time == 'Overdue' ? 0 : 1;
      if (aOverdue != bOverdue) return aOverdue - bOverdue;
      return b.createdAt.compareTo(a.createdAt);
    });

    if (mounted) setState(() { _alerts = alerts; _isLoading = false; });
  }

  Color _typeColor(_AlertType t) {
    switch (t) {
      case _AlertType.task:       return const Color(0xFF3b82f6);
      case _AlertType.milestone:  return const Color(0xFFf59e0b);
      case _AlertType.inspection: return const Color(0xFF10b981);
      case _AlertType.risk:       return const Color(0xFFef4444);
      case _AlertType.update:     return const Color(0xFF8b5cf6);
    }
  }

  IconData _typeIcon(_AlertType t) {
    switch (t) {
      case _AlertType.task:       return Icons.assignment_rounded;
      case _AlertType.milestone:  return Icons.flag_rounded;
      case _AlertType.inspection: return Icons.fact_check_rounded;
      case _AlertType.risk:       return Icons.warning_amber_rounded;
      case _AlertType.update:     return Icons.update_rounded;
    }
  }

  String _typeLabel(_AlertType t) {
    switch (t) {
      case _AlertType.task:       return 'Task';
      case _AlertType.milestone:  return 'Milestone';
      case _AlertType.inspection: return 'Inspection';
      case _AlertType.risk:       return 'Risk';
      case _AlertType.update:     return 'Update';
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _alerts.where((a) => !a.read).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Notifications', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1e293b),
        elevation: 0,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: const Color(0xFFe2e8f0))),
        actions: [
          if (unread > 0)
            Container(margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFef4444), borderRadius: BorderRadius.circular(20)),
              child: Text('$unread new', style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadNotifications, tooltip: 'Refresh'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _alerts.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.notifications_none_rounded, size: 64, color: Color(0xFFcbd5e1)),
                  const SizedBox(height: 16),
                  Text('All clear!', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18, color: const Color(0xFF1e293b))),
                  const SizedBox(height: 4),
                  Text('No notifications at this time.', style: GoogleFonts.inter(color: const Color(0xFF64748b))),
                ]))
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _alerts.length,
                    itemBuilder: (ctx, i) {
                      final alert = _alerts[i];
                      final color = _typeColor(alert.type);
                      final isOverdue = alert.time == 'Overdue';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isOverdue ? const Color(0xFFfecaca) : (alert.read ? const Color(0xFFe2e8f0) : color.withOpacity(0.3))),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                            child: Icon(_typeIcon(alert.type), color: color, size: 20),
                          ),
                          title: Row(children: [
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text(_typeLabel(alert.type), style: GoogleFonts.inter(color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                            ),
                            Flexible(child: Text(alert.title,
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: alert.read ? FontWeight.w500 : FontWeight.w700, color: const Color(0xFF0f172a)),
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
                            if (!alert.read) ...[
                              const SizedBox(width: 6),
                              Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            ],
                          ]),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const SizedBox(height: 4),
                            Text(alert.body, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748b)), maxLines: 3, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            Text(alert.time, style: GoogleFonts.inter(fontSize: 11,
                                color: isOverdue ? const Color(0xFFef4444) : const Color(0xFF94a3b8),
                                fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w400)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
