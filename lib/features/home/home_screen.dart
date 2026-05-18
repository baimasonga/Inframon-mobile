import 'package:flutter/material.dart';
  import 'package:google_fonts/google_fonts.dart';
  import 'package:provider/provider.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import '../../main.dart';
  import '../../core/database/db_helper.dart';
  import '../sync/sync_provider.dart';
  import '../tasks/tasks_screen.dart';

  class HomeScreen extends StatefulWidget {
    const HomeScreen({super.key});

    @override
    State<HomeScreen> createState() => _HomeScreenState();
  }

  class _HomeScreenState extends State<HomeScreen> {
    String _displayName = 'Inspector';
    int _pendingVisits = 0;
    int _pendingIssues = 0;
    int _pendingTasks = 0;

    // ── Notification banner state ─────────────────────────────────────────────
    bool _showBanner = false;
    Map<String, dynamic>? _bannerTask;

    @override
    void initState() {
      super.initState();
      _loadLocalStats();

      // Start Realtime subscription after auth is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
          context.read<SyncProvider>().startRealtimeSubscription(userId);
        }
      });
    }

    @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      // Watch for new task notifications from Realtime
      final newTask = context.read<SyncProvider>().latestNewTask;
      if (newTask != null && newTask != _bannerTask) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _bannerTask = newTask;
              _showBanner = true;
              _pendingTasks++;
            });
            // Auto-dismiss after 8 seconds
            Future.delayed(const Duration(seconds: 8), () {
              if (mounted) setState(() => _showBanner = false);
            });
          }
        });
      }
    }

    Future<void> _loadLocalStats() async {
      final db = await DatabaseHelper.instance.database;

      final profile = await db.query('user_profile', limit: 1);
      if (profile.isNotEmpty && mounted) {
        setState(() => _displayName = profile.first['full_name'] as String? ?? 'Inspector');
      } else {
        final email = Supabase.instance.client.auth.currentUser?.email ?? '';
        if (mounted) {
          setState(() => _displayName = email.contains('@') ? email.split('@')[0] : 'Inspector');
        }
      }

      final visitsResult = await db.rawQuery(
        "SELECT COUNT(*) as c FROM visit_metadata WHERE sync_status = 'pending'",
      );
      final issuesResult = await db.rawQuery(
        "SELECT COUNT(*) as c FROM issues WHERE sync_status = 'pending'",
      );
      final tasksResult = await db.rawQuery(
        "SELECT COUNT(*) as c FROM inspection_tasks WHERE status != 'Completed'",
      );

      if (mounted) {
        setState(() {
          _pendingVisits = (visitsResult.first['c'] as int?) ?? 0;
          _pendingIssues = (issuesResult.first['c'] as int?) ?? 0;
          _pendingTasks  = (tasksResult.first['c']  as int?) ?? 0;
        });
      }
    }

    Future<void> _signOut(BuildContext context) async {
      context.read<SyncProvider>().stopRealtimeSubscription();
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }

    void _dismissBanner() {
      setState(() => _showBanner = false);
      context.read<SyncProvider>().clearLatestTaskNotification();
    }

    void _openTasks() {
      _dismissBanner();
      Navigator.push(context, MaterialPageRoute(builder: (_) => const TasksScreen()));
    }

    String _greeting() {
      final h = DateTime.now().hour;
      if (h < 12) return 'Good morning,';
      if (h < 17) return 'Good afternoon,';
      return 'Good evening,';
    }

    @override
    Widget build(BuildContext context) {
      final syncProvider = context.watch<SyncProvider>();

      // Show banner when latestNewTask changes
      if (syncProvider.latestNewTask != null &&
          syncProvider.latestNewTask != _bannerTask) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_showBanner) {
            setState(() {
              _bannerTask = syncProvider.latestNewTask;
              _showBanner = true;
              _pendingTasks++;
            });
            Future.delayed(const Duration(seconds: 8), () {
              if (mounted) setState(() => _showBanner = false);
            });
          }
        });
      }

      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          children: [
            // ── Main scroll content ────────────────────────────────────────────
            CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 160,
                  floating: false,
                  pinned: true,
                  backgroundColor: AppColors.navy,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.navy, Color(0xFF0A3260)],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_greeting(),
                                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white60)),
                                  Text(_displayName,
                                      style: GoogleFonts.inter(
                                          fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                              const Spacer(),
                              // Realtime status dot
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: syncProvider.isSyncing ? AppColors.amber : AppColors.success,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(
                                    color: (syncProvider.isSyncing ? AppColors.amber : AppColors.success).withValues(alpha: 0.5),
                                    blurRadius: 6, spreadRadius: 2,
                                  )],
                                ),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.logout, color: Colors.white54, size: 20),
                                tooltip: 'Sign Out',
                                onPressed: () => _signOut(context),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () async {
                                  await syncProvider.syncNow();
                                  if (mounted) _loadLocalStats();
                                },
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Row(
                                        children: [
                                          syncProvider.isSyncing
                                              ? const SizedBox(width: 14, height: 14,
                                                  child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2))
                                              : const Icon(Icons.sync, size: 14, color: Colors.white70),
                                          const SizedBox(width: 8),
                                          Text(
                                            syncProvider.isSyncing ? 'Syncing...' : 'Sync',
                                            style: GoogleFonts.inter(
                                                fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (syncProvider.pendingCount > 0)
                                      Positioned(
                                        top: -6, right: -6,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(color: AppColors.amber, shape: BoxShape.circle),
                                          child: Text(
                                            '${syncProvider.pendingCount}',
                                            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([

                      // ── Unread task count badge ──────────────────────────
                      if (syncProvider.unreadTaskCount > 0)
                        GestureDetector(
                          onTap: _openTasks,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D6AE5).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF1D6AE5).withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.notifications_active, color: Color(0xFF1D6AE5), size: 18),
                                const SizedBox(width: 10),
                                Text(
                                  '${syncProvider.unreadTaskCount} new task${syncProvider.unreadTaskCount == 1 ? "" : "s"} assigned to you',
                                  style: GoogleFonts.inter(
                                      fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1D6AE5)),
                                ),
                                const Spacer(),
                                Text('View →', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF1D6AE5))),
                              ],
                            ),
                          ),
                        ),

                      // ── Stat cards ───────────────────────────────────────
                      _StatCard(
                        label: 'Pending Reports',
                        value: _pendingVisits,
                        icon: Icons.assignment_outlined,
                        color: AppColors.amber,
                        onTap: () {},
                      ),
                      const SizedBox(height: 12),
                      _StatCard(
                        label: 'Open Issues',
                        value: _pendingIssues,
                        icon: Icons.warning_amber_outlined,
                        color: AppColors.danger,
                        onTap: () {},
                      ),
                      const SizedBox(height: 12),
                      _StatCard(
                        label: 'Active Tasks',
                        value: _pendingTasks,
                        icon: Icons.task_alt,
                        color: AppColors.blue,
                        onTap: _openTasks,
                      ),
                      const SizedBox(height: 20),

                      // ── Connection status ────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(
                                color: syncProvider.isSyncing ? AppColors.amber : AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                syncProvider.isSyncing
                                    ? 'Syncing data to InfraMon server…'
                                    : syncProvider.lastSyncTime != null
                                        ? 'Live — last synced ${_timeAgo(syncProvider.lastSyncTime!)}'
                                        : 'Live connection active — listening for updates',
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ),
                            if (syncProvider.pendingCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(
                                  '${syncProvider.pendingCount} pending',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.amber),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),

            // ── Floating notification banner ───────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              top: _showBanner ? MediaQuery.of(context).padding.top + 12 : -160,
              left: 16,
              right: 16,
              child: _NewTaskBanner(
                task: _bannerTask,
                onTap: _openTasks,
                onDismiss: _dismissBanner,
              ),
            ),
          ],
        ),
      );
    }

    String _timeAgo(DateTime dt) {
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    }
  }

  // ── Floating notification banner widget ──────────────────────────────────────
  class _NewTaskBanner extends StatelessWidget {
    final Map<String, dynamic>? task;
    final VoidCallback onTap;
    final VoidCallback onDismiss;

    const _NewTaskBanner({
      required this.task,
      required this.onTap,
      required this.onDismiss,
    });

    @override
    Widget build(BuildContext context) {
      if (task == null) return const SizedBox.shrink();

      final priority = task!['priority'] as String? ?? 'Normal';
      final priorityColor = priority == 'Urgent'
          ? Colors.deepPurple
          : priority == 'High'
              ? AppColors.danger
              : priority == 'Low'
                  ? Colors.teal
                  : AppColors.amber;

      return Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black26,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1D6AE5).withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1D6AE5), Color(0xFF0A3260)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.assignment_add, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text('📋 ', style: TextStyle(fontSize: 12)),
                          Text(
                            'New Task Assigned',
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1D6AE5)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task!['title'] as String? ?? 'New inspection task',
                        style: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: priorityColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              priority,
                              style: GoogleFonts.inter(
                                  fontSize: 9, fontWeight: FontWeight.bold, color: priorityColor),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('Tap to view', style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                  onPressed: onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  // ── Stat card ─────────────────────────────────────────────────────────────────
  class _StatCard extends StatelessWidget {
    final String label;
    final int value;
    final IconData icon;
    final Color color;
    final VoidCallback? onTap;

    const _StatCard({
      required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.onTap,
    });

    @override
    Widget build(BuildContext context) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                    Text(
                      value.toString(),
                      style: GoogleFonts.inter(
                          fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            ],
          ),
        ),
      );
    }
  }
  