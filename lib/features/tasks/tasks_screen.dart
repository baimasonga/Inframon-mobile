import 'package:flutter/material.dart';
  import 'package:google_fonts/google_fonts.dart';
  import 'package:provider/provider.dart';
  import '../../core/database/db_helper.dart';
  import '../../main.dart';
  import '../sync/sync_provider.dart';
  import 'task_detail_screen.dart';

  class TasksScreen extends StatefulWidget {
    const TasksScreen({super.key});

    @override
    State<TasksScreen> createState() => _TasksScreenState();
  }

  class _TasksScreenState extends State<TasksScreen>
      with SingleTickerProviderStateMixin {
    late TabController _tabController;
    List<Map<String, dynamic>> _allTasks = [];
    bool _isLoading = true;
    bool _isRefreshing = false;

    @override
    void initState() {
      super.initState();
      _tabController = TabController(length: 3, vsync: this);
      _fetchTasks();
    }

    @override
    void dispose() {
      _tabController.dispose();
      super.dispose();
    }

    List<Map<String, dynamic>> get _pendingTasks =>
        _allTasks.where((t) => (t['status'] ?? 'Pending') == 'Pending').toList();
    List<Map<String, dynamic>> get _inProgressTasks =>
        _allTasks.where((t) => t['status'] == 'In Progress').toList();
    List<Map<String, dynamic>> get _completedTasks =>
        _allTasks.where((t) => t['status'] == 'Completed').toList();

    Future<void> _fetchTasks() async {
      try {
        final db = await DatabaseHelper.instance.database;
        final data = await db.query('inspection_tasks', orderBy: 'deadline ASC');
        if (mounted) {
          setState(() {
            _allTasks = List<Map<String, dynamic>>.from(data);
            _isLoading = false;
            _isRefreshing = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isRefreshing = false;
          });
        }
      }
    }

    Future<void> _refresh() async {
      if (_isRefreshing) return;
      setState(() => _isRefreshing = true);
      await context.read<SyncProvider>().syncNow();
      await _fetchTasks();
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('My Tasks'),
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            if (_isRefreshing)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
              )
            else
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'Sync from server',
                onPressed: _refresh,
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: AppColors.amber,
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
            tabs: [
              Tab(text: 'Pending (${_pendingTasks.length})'),
              Tab(text: 'In Progress (${_inProgressTasks.length})'),
              Tab(text: 'Done (${_completedTasks.length})'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_pendingTasks, 'Pending'),
                  _buildList(_inProgressTasks, 'In Progress'),
                  _buildList(_completedTasks, 'Completed'),
                ],
              ),
      );
    }

    Widget _buildList(List<Map<String, dynamic>> tasks, String type) {
      if (tasks.isEmpty) {
        final icon = type == 'Completed'
            ? Icons.check_circle_outline
            : type == 'In Progress'
                ? Icons.pending_actions_outlined
                : Icons.assignment_outlined;

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 64,
                  color: AppColors.textSecondary.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text(
                'No $type tasks',
                style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Pull down to refresh or tap sync\nto download the latest assignments.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.sync),
                label: const Text('Sync Now'),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: tasks.length,
          itemBuilder: (context, i) => _TaskCard(
            task: tasks[i],
            onTap: () async {
              final refreshed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) => TaskDetailScreen(task: tasks[i])),
              );
              if (refreshed == true) _fetchTasks();
            },
          ),
        ),
      );
    }
  }

  // ── Task Card ────────────────────────────────────────────────────────────────
  class _TaskCard extends StatelessWidget {
    final Map<String, dynamic> task;
    final VoidCallback onTap;
    const _TaskCard({required this.task, required this.onTap});

    Color _priorityColor(String p) {
      switch (p) {
        case 'Urgent': return Colors.deepPurple;
        case 'High':   return AppColors.danger;
        case 'Low':    return Colors.teal;
        default:       return AppColors.amber;
      }
    }

    @override
    Widget build(BuildContext context) {
      final priority = task['priority'] as String? ?? 'Normal';
      final status   = task['status']   as String? ?? 'Pending';
      final deadline = task['deadline'] as String?;
      final pc = _priorityColor(priority);

      final statusColor = status == 'Completed'
          ? AppColors.success
          : status == 'In Progress'
              ? AppColors.amber
              : AppColors.textSecondary;

      bool isOverdue = false;
      if (deadline != null) {
        try {
          isOverdue = DateTime.parse(deadline).isBefore(DateTime.now()) &&
              status != 'Completed';
        } catch (_) {}
      }

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: isOverdue
                  ? AppColors.danger.withValues(alpha: 0.4)
                  : const Color(0xFFE2E8F0)),
        ),
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Priority + overdue row
                Row(
                  children: [
                    _chip(priority, pc),
                    if (isOverdue) ...[
                      const SizedBox(width: 6),
                      _chip('OVERDUE', AppColors.danger, fontSize: 9),
                    ],
                    const Spacer(),
                    Icon(Icons.chevron_right,
                        color: AppColors.textSecondary, size: 20),
                  ],
                ),
                const SizedBox(height: 10),

                // Title
                Text(
                  task['title'] as String? ?? 'Untitled',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),

                // Description preview
                if ((task['description'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    task['description'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],

                const SizedBox(height: 12),

                // Footer: deadline + status
                Row(
                  children: [
                    if (deadline != null) ...[
                      Icon(Icons.calendar_today,
                          size: 12,
                          color: isOverdue
                              ? AppColors.danger
                              : AppColors.textSecondary),
                      const SizedBox(width: 3),
                      Text(
                        deadline,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isOverdue
                                ? AppColors.danger
                                : AppColors.textSecondary),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        status,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    const Spacer(),
                    if (task['gps_lat'] != null)
                      Icon(Icons.location_on,
                          size: 14, color: AppColors.success),
                    if (task['field_notes'] != null &&
                        (task['field_notes'] as String).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.notes,
                            size: 14, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget _chip(String text, Color color, {double fontSize = 10}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(text,
              style: GoogleFonts.inter(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: color)),
        );
  }
  