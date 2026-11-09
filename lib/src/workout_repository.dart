import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class WorkoutRepository {
  WorkoutRepository(this._client);

  static const _queueKey = 'get_fit_workout_outbox_v1';
  static const _assignmentCachePrefix = 'get_fit_assignment_v1_';
  static const _uuid = Uuid();
  static const _storage = FlutterSecureStorage();

  final SupabaseClient _client;
  bool _syncing = false;

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
    await _client.from('workout_assignments').insert({
      'trainer_id': _client.auth.currentUser!.id,
      'client_id': clientId,
      'plan_id': planId,
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
      if (sessionId != null) {
        active[assignmentId] = sessionId;
        await _writeQueue(queue);
      }
      return sessionId;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int>> loadSetCounts(String sessionId) async {
    final counts = <String, int>{};
    try {
      final rows = await _client
          .from('workout_set_logs')
          .select('plan_exercise_id, set_number')
          .eq('session_id', sessionId);
      for (final row in rows) {
        final exerciseId = row['plan_exercise_id'] as String;
        final setNumber = row['set_number'] as int;
        if (setNumber > (counts[exerciseId] ?? 0)) counts[exerciseId] = setNumber;
      }
    } catch (_) {}

    final queue = await _readQueue();
    for (final row in (queue['sets'] as List).cast<Map<String, dynamic>>()) {
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
      await _client.from('workout_set_logs').upsert(row, onConflict: 'id');
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
    final queue = await _readQueue();
    if ((queue['sessions'] as List).any((row) => row['id'] == sessionId)) {
      final completed = queue['completed'] as List;
      if (!completed.contains(sessionId)) completed.add(sessionId);
      (queue['active'] as Map<String, dynamic>).removeWhere((_, value) => value == sessionId);
      await _writeQueue(queue);
      return;
    }
    final update = {
      'status': 'completed',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (await _isOffline()) throw const _OfflineException();
      await _client.from('workout_sessions').update(update).eq('id', sessionId);
      final current = await _readQueue();
      (current['active'] as Map<String, dynamic>).removeWhere((_, value) => value == sessionId);
      await _writeQueue(current);
    } on _OfflineException {
      await _queueCompletion(sessionId);
    } on PostgrestException {
      rethrow;
    } catch (_) {
      await _queueCompletion(sessionId);
    }
  }

  Future<int> syncPending() async {
    if (_syncing || await _isOffline()) return 0;
    _syncing = true;
    var synced = 0;
    try {
      final queue = await _readQueue();
      final sessions = queue['sessions'] as List;
      while (sessions.isNotEmpty) {
        try {
          await _client.from('workout_sessions').upsert(sessions.first, onConflict: 'id');
          sessions.removeAt(0);
          await _writeQueue(queue);
          synced++;
        } catch (_) {
          return synced;
        }
      }

      final sets = queue['sets'] as List;
      while (sets.isNotEmpty) {
        try {
          await _client.from('workout_set_logs').upsert(sets.first, onConflict: 'id');
          sets.removeAt(0);
          await _writeQueue(queue);
          synced++;
        } catch (_) {
          return synced;
        }
      }

      final completed = queue['completed'] as List;
      while (completed.isNotEmpty) {
        try {
          await _client.from('workout_sessions').update({
            'status': 'completed',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', completed.first);
          (queue['active'] as Map<String, dynamic>).removeWhere((_, value) => value == completed.first);
          completed.removeAt(0);
          await _writeQueue(queue);
          synced++;
        } catch (_) {
          return synced;
        }
      }
      return synced;
    } finally {
      _syncing = false;
    }
  }

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
      };
    }
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    decoded['sessions'] ??= <dynamic>[];
    decoded['sets'] ??= <dynamic>[];
    decoded['completed'] ??= <dynamic>[];
    decoded['active'] ??= <String, dynamic>{};
    return decoded;
  }

  Future<void> _writeQueue(Map<String, dynamic> queue) =>
      _storage.write(key: _queueKey, value: jsonEncode(queue));

  Future<void> _queueSession(Map<String, dynamic> row) async {
    final queue = await _readQueue();
    final sessions = queue['sessions'] as List;
    if (!sessions.any((item) => item['id'] == row['id'])) sessions.add(row);
    await _writeQueue(queue);
  }

  Future<void> _queueSet(Map<String, dynamic> row) async {
    final queue = await _readQueue();
    final sets = queue['sets'] as List;
    if (!sets.any((item) => item['id'] == row['id'])) sets.add(row);
    await _writeQueue(queue);
  }

  Future<void> _queueCompletion(String sessionId) async {
    final queue = await _readQueue();
    final completed = queue['completed'] as List;
    if (!completed.contains(sessionId)) completed.add(sessionId);
    await _writeQueue(queue);
  }

  Future<void> _setActiveSession(String assignmentId, String sessionId) async {
    final queue = await _readQueue();
    (queue['active'] as Map<String, dynamic>)[assignmentId] = sessionId;
    await _writeQueue(queue);
  }
}

class _OfflineException implements Exception {
  const _OfflineException();
}