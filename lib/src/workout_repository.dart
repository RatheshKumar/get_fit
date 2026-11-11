import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

class WorkoutRepository {
  WorkoutRepository(this._client);

  static const _queueKeyPrefix = 'get_fit_workout_outbox_v1_';
  static const _assignmentCachePrefix = 'get_fit_assignment_v1_';
  static const _uuid = Uuid();
  static const _storage = FlutterSecureStorage();
  static final _outboxLock = Lock();

  final SupabaseClient _client;
  bool _syncing = false;

  String get _queueKey => '$_queueKeyPrefix${_client.auth.currentUser!.id}';

  String newId() => _uuid.v4();

  Future<bool> isOffline() => _isOffline();

  Future<List<Map<String, dynamic>>> loadPlans() async {
    final rows = await _client
        .from('workout_plans')
        .select('id, name, description, created_at')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> createPlan({required String name, required String description}) async {
    final row = await _client.from('workout_plans').insert({
      'trainer_id': _client.auth.currentUser!.id,
      'name': name.trim(),
      'description': description.trim(),
    }).select('id').single();
    return row['id'] as String;
  }

  Future<List<Map<String, dynamic>>> loadExercises() async {
    final rows = await _client
        .from('exercise_library')
        .select('id, name, instructions, media_url')
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> createExercise({
    required String name,
    required String instructions,
    String? mediaUrl,
  }) async {
    final row = await _client.from('exercise_library').insert({
      'trainer_id': _client.auth.currentUser!.id,
      'name': name.trim(),
      'instructions': instructions.trim(),
      'media_url': mediaUrl?.trim().isEmpty == true ? null : mediaUrl?.trim(),
    }).select('id').single();
    return row['id'] as String;
  }

  Future<void> addPlanExercise({
    required String planId,
    required String exerciseId,
    required int position,
    required int sets,
    required String reps,
    required int restSeconds,
    required String notes,
  }) async {
    await _client.from('workout_plan_exercises').insert({
      'plan_id': planId,
      'exercise_id': exerciseId,
      'position': position,
      'sets': sets,
      'reps': reps.trim(),
      'rest_seconds': restSeconds,
      'notes': notes.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> loadPlanExercises(String planId) async {
    final rows = await _client
        .from('workout_plan_exercises')
          .select('id, exercise_id, position, sets, reps, rest_seconds, notes, exercise_library(id, name, instructions, media_url)')
        .eq('plan_id', planId)
        .order('position');
    return List<Map<String, dynamic>>.from(rows);
  }

    Future<void> updatePlanExercise({
      required String itemId,
      required String exerciseId,
      required int sets,
      required String reps,
      required int restSeconds,
      required String notes,
    }) async {
      await _client.from('workout_plan_exercises').update({
        'exercise_id': exerciseId,
        'sets': sets,
        'reps': reps.trim(),
        'rest_seconds': restSeconds,
        'notes': notes.trim(),
      }).eq('id', itemId);
    }

  Future<void> assignPlan({required String clientId, required String planId}) async {
    await _client.rpc('assign_workout_plan', params: {
      'target_client_id': clientId,
      'target_plan_id': planId,
    });
  }

  Future<Map<String, dynamic>?> loadClientAssignment() async {
    final userId = _client.auth.currentUser!.id;
    final cacheKey = '$_assignmentCachePrefix$userId';
    try {
      final assignment = await _client
          .from('workout_assignments')
          .select(
            'id, client_id, plan_id, starts_on, created_at, workout_plans(id, name, description, '
            'workout_plan_exercises(id, exercise_id, position, sets, reps, rest_seconds, notes, '
            'exercise_library(id, name, instructions, media_url)))',
          )
          .eq('is_active', true)
          .order('starts_on', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (assignment == null) {
        await _storage.delete(key: cacheKey);
        return null;
      }
      await _storage.write(key: cacheKey, value: jsonEncode(assignment));
      return assignment;
    } catch (error) {
      final cached = await _storage.read(key: cacheKey);
      if (cached == null) rethrow;
      return Map<String, dynamic>.from(jsonDecode(cached) as Map);
    }
  }

  Future<String?> findActiveSession(String assignmentId) async {
    final queue = await _readQueue();
    final active = queue['active'] as Map<String, dynamic>;
    final locallyActive = active[assignmentId] as String?;
    if (locallyActive != null && !(queue['completed'] as List).contains(locallyActive)) {
      return locallyActive;
    }
    final pending = (queue['sessions'] as List).cast<Map<String, dynamic>>();
    final completed = (queue['completed'] as List).cast<String>().toSet();
    for (final session in pending) {
      if (session['assignment_id'] == assignmentId && !completed.contains(session['id'])) {
        return session['id'] as String;
      }
    }
    try {
      final session = await _client
          .from('workout_sessions')
          .select('id')
          .eq('assignment_id', assignmentId)
          .eq('status', 'active')
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final sessionId = session?['id'] as String?;
      if (sessionId != null && !completed.contains(sessionId)) {
        await _setActiveSession(assignmentId, sessionId);
      } else if (sessionId != null) {
        return null;
      }
      return sessionId;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int>> loadSetCounts(String sessionId) async {
    final counts = <String, int>{};
    if (!await _isOffline()) {
      final rows = await _client
          .from('workout_set_logs')
          .select('plan_exercise_id, set_number')
          .eq('session_id', sessionId);
      for (final row in rows) {
        final exerciseId = row['plan_exercise_id'] as String;
        final setNumber = row['set_number'] as int;
        if (setNumber > (counts[exerciseId] ?? 0)) counts[exerciseId] = setNumber;
      }
    }

    final queue = await _readQueue();
    final cached = ((queue['counts'] as Map<String, dynamic>)[sessionId] as List? ?? [])
        .cast<Map<String, dynamic>>();
    for (final row in [
      ...cached,
      ...(queue['sets'] as List).cast<Map<String, dynamic>>(),
    ]) {
      if (row['session_id'] != sessionId) continue;
      final exerciseId = row['plan_exercise_id'] as String;
      final setNumber = row['set_number'] as int;
      if (setNumber > (counts[exerciseId] ?? 0)) counts[exerciseId] = setNumber;
    }
    return counts;
  }

  Future<String> startSession({required String assignmentId, required String clientId}) async {
    final row = {
      'id': newId(),
      'assignment_id': assignmentId,
      'client_id': clientId,
      'started_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (await _isOffline()) throw const _OfflineException();
      await _client.from('workout_sessions').insert(row);
    } on _OfflineException {
      await _queueSession(row);
    } on PostgrestException {
      rethrow;
    } catch (_) {
      await _queueSession(row);
    }
    await _setActiveSession(assignmentId, row['id']!);
    return row['id']!;
  }

  Future<bool> saveSet({
    required String sessionId,
    required String planExerciseId,
    required int setNumber,
    required int reps,
    required double weightKg,
  }) async {
    final row = {
      'id': newId(),
      'session_id': sessionId,
      'plan_exercise_id': planExerciseId,
      'set_number': setNumber,
      'reps_completed': reps,
      'weight_kg': weightKg,
      'logged_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (await _isOffline()) throw const _OfflineException();
      await _client.from('workout_set_logs').insert(row);
      await _cacheSet(row);
      return true;
    } on _OfflineException {
      await _queueSet(row);
      return false;
    } on PostgrestException {
      rethrow;
    } catch (_) {
      await _queueSet(row);
      return false;
    }
  }

  Future<void> completeSession(String sessionId) async {
    final pending = await _mutateQueue<bool>((queue) async {
      if (!(queue['sessions'] as List).any((row) => row['id'] == sessionId)) return false;
      final completed = queue['completed'] as List;
      if (!completed.contains(sessionId)) completed.add(sessionId);
      (queue['active'] as Map<String, dynamic>).removeWhere((_, value) => value == sessionId);
      return true;
    });
    if (pending) return;
    final update = {
      'status': 'completed',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (await _isOffline()) throw const _OfflineException();
      await _client.from('workout_sessions').update(update).eq('id', sessionId);
      await _mutateQueue<void>((queue) async {
        (queue['active'] as Map<String, dynamic>).removeWhere((_, value) => value == sessionId);
      });
    } on _OfflineException {
      await _queueCompletion(sessionId);
    } on PostgrestException {
      rethrow;
    } catch (_) {
      await _queueCompletion(sessionId);
    }
  }

  Future<WorkoutSyncResult> syncPending() async {
    if (_syncing) return const WorkoutSyncResult(busy: true);
    _syncing = true;
    var synced = 0;
    try {
      if (await _isOffline()) return const WorkoutSyncResult(offline: true);
      while (true) {
        final sessions = (await _readQueue())['sessions'] as List;
        if (sessions.isEmpty) break;
        final row = Map<String, dynamic>.from(sessions.first as Map);
        try {
          await _client.from('workout_sessions').upsert(
                row,
                onConflict: 'id',
                ignoreDuplicates: true,
              );
          await _removeQueuedRow('sessions', row['id']);
          synced++;
        } catch (error) {
          return WorkoutSyncResult(syncedCount: synced, error: _errorMessage(error));
        }
      }

      while (true) {
        final sets = (await _readQueue())['sets'] as List;
        if (sets.isEmpty) break;
        final row = Map<String, dynamic>.from(sets.first as Map);
        try {
          await _client.from('workout_set_logs').upsert(
                row,
                onConflict: 'id',
                ignoreDuplicates: true,
              );
          await _removeQueuedRow('sets', row['id']);
          synced++;
        } catch (error) {
          return WorkoutSyncResult(syncedCount: synced, error: _errorMessage(error));
        }
      }

      while (true) {
        final completed = (await _readQueue())['completed'] as List;
        if (completed.isEmpty) break;
        final sessionId = completed.first as String;
        try {
          await _client.from('workout_sessions').update({
            'status': 'completed',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', sessionId);
          await _mutateQueue<void>((queue) async {
            (queue['completed'] as List).remove(sessionId);
            (queue['active'] as Map<String, dynamic>).removeWhere((_, value) => value == sessionId);
            (queue['counts'] as Map<String, dynamic>).remove(sessionId);
          });
          synced++;
        } catch (error) {
          return WorkoutSyncResult(syncedCount: synced, error: _errorMessage(error));
        }
      }
      return WorkoutSyncResult(syncedCount: synced);
    } catch (error) {
      return WorkoutSyncResult(syncedCount: synced, error: _errorMessage(error));
    } finally {
      _syncing = false;
    }
  }

  String _errorMessage(Object error) => error is PostgrestException
      ? error.message
      : 'Some workout data could not sync. It remains saved on this device.';

  Future<bool> _isOffline() async {
    final connectivity = await Connectivity().checkConnectivity();
    return connectivity.every((result) => result == ConnectivityResult.none);
  }

  Future<Map<String, dynamic>> _readQueue() async {
    final encoded = await _storage.read(key: _queueKey);
    if (encoded == null) {
      return {
        'sessions': <dynamic>[],
        'sets': <dynamic>[],
        'completed': <dynamic>[],
        'active': <String, dynamic>{},
        'counts': <String, dynamic>{},
      };
    }
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    decoded['sessions'] ??= <dynamic>[];
    decoded['sets'] ??= <dynamic>[];
    decoded['completed'] ??= <dynamic>[];
    decoded['active'] ??= <String, dynamic>{};
    decoded['counts'] ??= <String, dynamic>{};
    return decoded;
  }

  Future<void> _writeQueue(Map<String, dynamic> queue) =>
      _storage.write(key: _queueKey, value: jsonEncode(queue));

  Future<T> _mutateQueue<T>(Future<T> Function(Map<String, dynamic>) change) =>
      _outboxLock.synchronized(() async {
        final queue = await _readQueue();
        final result = await change(queue);
        await _writeQueue(queue);
        return result;
      });

  Future<void> _removeQueuedRow(String listKey, dynamic id) async {
    await _mutateQueue<void>((queue) async {
      (queue[listKey] as List).removeWhere((row) => row['id'] == id);
    });
  }

  Future<void> _queueSession(Map<String, dynamic> row) => _mutateQueue<void>((queue) async {
        final sessions = queue['sessions'] as List;
        if (!sessions.any((item) => item['id'] == row['id'])) sessions.add(row);
      });

  Future<void> _queueSet(Map<String, dynamic> row) => _mutateQueue<void>((queue) async {
        final sets = queue['sets'] as List;
        if (!sets.any((item) => item['id'] == row['id'])) sets.add(row);
      _cacheSetInQueue(queue, row);
      });

  Future<void> _queueCompletion(String sessionId) => _mutateQueue<void>((queue) async {
        final completed = queue['completed'] as List;
        if (!completed.contains(sessionId)) completed.add(sessionId);
      (queue['active'] as Map<String, dynamic>).removeWhere((_, value) => value == sessionId);
      });

  Future<void> _setActiveSession(String assignmentId, String sessionId) =>
      _mutateQueue<void>((queue) async {
        (queue['active'] as Map<String, dynamic>)[assignmentId] = sessionId;
      });

  Future<void> _cacheSet(Map<String, dynamic> row) => _mutateQueue<void>((queue) async {
        _cacheSetInQueue(queue, row);
      });

  void _cacheSetInQueue(Map<String, dynamic> queue, Map<String, dynamic> row) {
    final counts = queue['counts'] as Map<String, dynamic>;
    final sessionRows = (counts[row['session_id']] as List?) ?? <dynamic>[];
    if (!sessionRows.any((item) => item['id'] == row['id'])) sessionRows.add(row);
    counts[row['session_id'] as String] = sessionRows;
  }
}

class _OfflineException implements Exception {
  const _OfflineException();
}

class WorkoutSyncResult {
  const WorkoutSyncResult({this.syncedCount = 0, this.offline = false, this.busy = false, this.error});

  final int syncedCount;
  final bool offline;
  final bool busy;
  final String? error;
}