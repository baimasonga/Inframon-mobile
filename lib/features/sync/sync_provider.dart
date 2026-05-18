import 'dart:async';
import 'dart:convert';
import 'dart:io';
  import 'package:flutter/foundation.dart';
  import 'package:connectivity_plus/connectivity_plus.dart';
  import 'package:sqflite/sqflite.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import '../../core/database/db_helper.dart';

  class SyncProvider with ChangeNotifier {
    // Per-item failures above this count are skipped (not deleted) so the rest
    // of the queue can drain. Bad rows surface in last_error for inspection.
    static const int _maxRetries = 5;

    bool _isSyncing = false;
    bool get isSyncing => _isSyncing;
    DateTime? _lastSyncTime;
    DateTime? get lastSyncTime => _lastSyncTime;

    int _pendingCount = 0;
    int get pendingCount => _pendingCount;

    bool _isOnline = true;
    bool get isOnline => _isOnline;

    // ── Realtime notification state ───────────────────────────────────────────
    RealtimeChannel? _channel;
    Map<String, dynamic>? _latestNewTask;
    int _unreadTaskCount = 0;
    StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

    Map<String, dynamic>? get latestNewTask => _latestNewTask;
    int get unreadTaskCount => _unreadTaskCount;

    SyncProvider() {
      updatePendingCount();
      _tryStartRealtime();
      _startConnectivityWatch();
    }

    // ── Auto-sync when connectivity returns ───────────────────────────────────
    Future<void> _startConnectivityWatch() async {
      final connectivity = Connectivity();
      // Seed current state so isOnline is correct on first read.
      try {
        final initial = await connectivity.checkConnectivity();
        _isOnline = _hasNetwork(initial);
      } catch (_) {
        _isOnline = true; // fail open — let syncNow surface its own error
      }
      _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
        final wasOnline = _isOnline;
        _isOnline = _hasNetwork(results);
        notifyListeners();
        if (!wasOnline && _isOnline && !_isSyncing && _pendingCount > 0) {
          debugPrint('[Sync] Connectivity restored — auto-syncing $_pendingCount item(s)');
          // Fire-and-forget; syncNow guards against re-entry.
          unawaited(syncNow());
        }
      });
    }

    bool _hasNetwork(List<ConnectivityResult> results) {
      return results.any((r) =>
          r != ConnectivityResult.none && r != ConnectivityResult.bluetooth);
    }

    // ── Start Realtime subscription once auth is available ────────────────────
    Future<void> _tryStartRealtime() async {
      // Wait briefly for auth to settle
      await Future.delayed(const Duration(seconds: 2));
      final userId = _supabase?.auth.currentUser?.id;
      if (userId != null) startRealtimeSubscription(userId);
    }

    void startRealtimeSubscription(String userId) {
      stopRealtimeSubscription(); // Clean up any existing channel

      _channel = _supabase?.channel('task_feed_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'inspection_tasks',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'assignee_id',
              value: userId,
            ),
            callback: (payload) async {
              debugPrint('[Realtime] New task assigned: ${payload.newRecord}');
              await _handleNewTask(payload.newRecord);
            },
          )
          .subscribe((status, error) {
            debugPrint('[Realtime] Channel status: $status  error: $error');
          });
    }

    void stopRealtimeSubscription() {
      _channel?.unsubscribe();
      _channel = null;
    }

    Future<void> _handleNewTask(Map<String, dynamic> record) async {
      try {
        final db = await DatabaseHelper.instance.database;

        // Save to local SQLite
        await db.insert(
          'inspection_tasks',
          {
            'id':          record['id']?.toString(),
            'project_id':  record['project_id']?.toString(),
            'assignee_id': record['assignee_id']?.toString(),
            'title':       record['title']?.toString(),
            'description': record['description']?.toString(),
            'deadline':    record['deadline']?.toString(),
            'priority':    record['priority']?.toString() ?? 'Normal',
            'status':      record['status']?.toString() ?? 'Pending',
            'sync_status': 'synced',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Update notification state
        _latestNewTask = Map<String, dynamic>.from(record);
        _unreadTaskCount++;
        notifyListeners();
      } catch (e) {
        debugPrint('[Realtime] Failed to handle new task: $e');
      }
    }

    void clearLatestTaskNotification() {
      _latestNewTask = null;
      notifyListeners();
    }

    void markTasksRead() {
      _unreadTaskCount = 0;
      notifyListeners();
    }

    @override
    void dispose() {
      stopRealtimeSubscription();
      _connectivitySub?.cancel();
      _connectivitySub = null;
      super.dispose();
    }

    SupabaseClient? get _supabase {
      try {
        return Supabase.instance.client;
      } catch (e) {
        return null;
      }
    }

    Future<void> updatePendingCount() async {
      final db = await DatabaseHelper.instance.database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM sync_queue');
      _pendingCount = (result.first['count'] as int?) ?? 0;
      notifyListeners();
    }

    Future<void> syncNow() async {
      if (_isSyncing) return;

      _isSyncing = true;
      notifyListeners();

      try {
        final db = await DatabaseHelper.instance.database;
        // Only attempt items still under the retry cap. Persistently-failing
        // rows stay in the table (with last_error) so they can be inspected
        // and re-queued manually instead of silently dropped.
        final queue = await db.query(
          'sync_queue',
          where: 'retry_count < ?',
          whereArgs: [_maxRetries],
          orderBy: 'id ASC',
        );

        for (final item in queue) {
          final id        = item['id'] as int;
          final type      = item['entity_type'] as String;
          final operation = item['operation'] as String;
          final payload   = jsonDecode(item['payload'] as String);
          final retries   = (item['retry_count'] as int?) ?? 0;

          try {
            if (_supabase != null) {
              if (type == 'field_report') {
                // Try the RPC first; fall back to direct insert if it doesn't exist yet
                try {
                  await _supabase!.rpc('submit_field_report', params: {'report': payload});
                } catch (rpcErr) {
                  debugPrint('[Sync] RPC submit_field_report failed ($rpcErr). Falling back to direct insert.');
                  // Map the mobile payload fields to actual Supabase visit_metadata columns
                  await _supabase!.from('visit_metadata').upsert({
                    'id':                     payload['id'],
                    'project_id':             payload['project_id'],
                    'inspector_id':           payload['inspector_id'],
                    'visit_type':             payload['visit_type'],
                    'visit_date':             payload['date_time'] ?? payload['visit_date'],
                    'weather':                payload['weather_condition'] ?? payload['weather'],
                    'site_supervisor_present': payload['site_supervisor_present'],
                    'gps_lat':                payload['gps_lat'],
                    'gps_lng':                payload['gps_lng'],
                    'overall_progress':       payload['overall_progress'],
                    'overall_status':         payload['overall_status'],
                    'recommendation':         payload['recommendation'],
                    'notes':                  payload['notes'],
                  });
                }
              } else if (type == 'inspection_task_update') {
                final taskId = payload['id'].toString();
                final Map<String, dynamic> updateFields = {'status': payload['status']};
                if (payload['gps_lat'] != null) updateFields['gps_lat'] = payload['gps_lat'];
                if (payload['gps_lng'] != null) updateFields['gps_lng'] = payload['gps_lng'];
                await _supabase!.from('inspection_tasks').update(updateFields).eq('id', taskId);
              } else if (operation == 'INSERT') {
                final String tableName;
                if (type == 'workforce_record') {
                  tableName = 'workforce_records';
                } else if (type == 'issue') {
                  tableName = 'issues';
                } else if (type == 'inspection') {
                  tableName = 'inspections';
                } else if (type == 'attendance_log') {
                  tableName = 'attendance_logs';
                } else {
                  tableName = type;
                }
                await _supabase!.from(tableName).insert(payload);
              }
            }

            await Future.delayed(const Duration(milliseconds: 400));
            await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);

            if (type == 'field_report') {
              await db.update(
                'visit_metadata',
                {'sync_status': 'synced'},
                where: 'id = ?',
                whereArgs: [item['entity_id']],
              );
            } else if (type == 'issue') {
              await db.update(
                'issues',
                {'sync_status': 'synced'},
                where: 'id = ?',
                whereArgs: [item['entity_id']],
              );
            } else if (type == 'attendance_log') {
              await db.update(
                'attendance_records',
                {'sync_status': 'synced'},
                where: 'id = ?',
                whereArgs: [item['entity_id']],
              );
            }
          } catch (e) {
            // Don't halt the queue — record the failure on this row and move on.
            // Network outages bump every remaining row's retry once; persistent
            // schema/RLS errors will eventually exceed _maxRetries and be skipped.
            debugPrint('Sync failed for queue item $id (retry ${retries + 1}/$_maxRetries): $e');
            await db.update(
              'sync_queue',
              {
                'retry_count': retries + 1,
                'last_error': e.toString(),
              },
              where: 'id = ?',
              whereArgs: [id],
            );
            continue;
          }
        }

        _lastSyncTime = DateTime.now();

        // ── Photo Upload ──────────────────────────────────────────────────────
        await _uploadPendingPhotos(db);

        // ── Download Sync ────────────────────────────────────────────────────
        if (_supabase != null) {
          final userId = _supabase!.auth.currentUser?.id;
          if (userId != null) {
            // 1. Fetch Profile
            try {
              final profile = await _supabase!
                  .from('users')
                  .select()
                  .eq('id', userId)
                  .single();
              await db.insert(
                'user_profile',
                {
                  'id': profile['id'],
                  'full_name': profile['full_name'],
                  'role': profile['role'],
                  'assigned_districts': jsonEncode(profile['assigned_districts'] ?? []),
                  'specializations':    jsonEncode(profile['specializations']    ?? []),
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            } catch (e) {
              debugPrint('Profile fetch failed: $e');
            }

            // 2. Clear local project cache
            await db.delete('projects');
            await db.delete('inspection_tasks');

            // 3. Fetch Projects
            final profileRows = await db.query('user_profile', limit: 1);
            final List<String> districts = profileRows.isNotEmpty
                ? List<String>.from(
                    jsonDecode(profileRows.first['assigned_districts'] as String? ?? '[]'))
                : [];

            final assignedProjResponse = await _supabase!
                .from('project_assignments')
                .select('project_id')
                .eq('user_id', userId);
            final List<String> assignedIds =
                (assignedProjResponse as List<dynamic>)
                    .map((p) => p['project_id'].toString())
                    .toList();

            final Set<String> seenIds = {};
            final List<dynamic> allProjects = [];

            if (districts.isNotEmpty) {
              final dp = await _supabase!
                  .from('projects')
                  .select()
                  .inFilter('district', districts);
              for (var p in dp as List<dynamic>) {
                if (seenIds.add(p['id'].toString())) allProjects.add(p);
              }
            }
            if (assignedIds.isNotEmpty) {
              final dp = await _supabase!
                  .from('projects')
                  .select()
                  .inFilter('id', assignedIds);
              for (var p in dp as List<dynamic>) {
                if (seenIds.add(p['id'].toString())) allProjects.add(p);
              }
            }

            for (var p in allProjects) {
              await db.insert(
                'projects',
                {
                  'id':                    p['id'],
                  'name':                  p['name'],
                  'description':           p['description'],
                  'status':                p['status'],
                  'district':              p['district'],
                  'completion_percentage': p['completion_percentage'] ?? 0,
                  'created_at':            p['created_at'],
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }

            // 4. Fetch Tasks assigned to me
            final tasks = await _supabase!
                .from('inspection_tasks')
                .select()
                .eq('assignee_id', userId);
            for (var t in tasks as List<dynamic>) {
              await db.insert(
                'inspection_tasks',
                {
                  'id':          t['id'],
                  'project_id':  t['project_id'],
                  'assignee_id': t['assignee_id'],
                  'title':       t['title'],
                  'description': t['description'],
                  'deadline':    t['deadline'],
                  'priority':    t['priority'],
                  'status':      t['status'] ?? 'Pending',
                  'sync_status': 'synced',
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Sync critical error: $e');
      } finally {
        _isSyncing = false;
          await updatePendingCount();
          notifyListeners();
        }
      }

    Future<void> _uploadPendingPhotos(Database db) async {
      if (_supabase == null) return;
      const String bucket = 'inspection-photos';
      final List<Map<String, dynamic>> pending = await db.query(
        'inspection_photos',
        where: "sync_status = 'pending' AND retry_count < ?",
        whereArgs: [_maxRetries],
      );
      for (final row in pending) {
        final int rowId      = row['id'] as int;
        final String visitId = row['visit_id'] as String;
        final String path    = row['local_path'] as String;
        try {
          final File file = File(path);
          if (!await file.exists()) {
            await db.update('inspection_photos', {'sync_status': 'orphaned'}, where: 'id = ?', whereArgs: [rowId]);
            continue;
          }
          final Uint8List bytes = await file.readAsBytes();
          final String rawExt = path.split('.').last.toLowerCase();
          // Only allow known image extensions; default to jpg.
          final String ext = (rawExt == 'png' || rawExt == 'jpg' || rawExt == 'jpeg')
              ? rawExt
              : 'jpg';
          // Strip anything that isn't [A-Za-z0-9_-] to defeat path traversal.
          final String safeVisitId =
              visitId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
          if (safeVisitId.isEmpty) {
            debugPrint('[PhotoSync] Skipping photo $rowId: empty visit id');
            continue;
          }
          final String storagePath =
              'retry/$safeVisitId/${rowId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
          await _supabase!.storage
              .from(bucket)
              .uploadBinary(
                storagePath,
                bytes,
                fileOptions: FileOptions(
                  contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
                  upsert: true,
                ),
              );
          final String url = _supabase!.storage.from(bucket).getPublicUrl(storagePath);
          await db.update(
            'inspection_photos',
            {'remote_url': url, 'sync_status': 'synced'},
            where: 'id = ?',
            whereArgs: [rowId],
          );
          debugPrint('[PhotoSync] Uploaded pending photo $rowId');
        } catch (e) {
          debugPrint('[PhotoSync] Failed to upload photo $rowId: $e');
          await db.rawUpdate(
            'UPDATE inspection_photos SET retry_count = retry_count + 1 WHERE id = ?',
            [rowId],
          );
        }
      }
    }
  }
  