import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'workout_repository.dart';

class ClientWorkoutScreen extends StatefulWidget {
  const ClientWorkoutScreen({super.key});

  @override
  State<ClientWorkoutScreen> createState() => _ClientWorkoutScreenState();
}

class _ClientWorkoutScreenState extends State<ClientWorkoutScreen> with WidgetsBindingObserver {
  final _repository = WorkoutRepository(Supabase.instance.client);
  late Future<_WorkoutViewData?> _workout;
  RealtimeChannel? _workoutChannel;
  String? _watchedPlan;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String? _sessionId;
  final Map<String, int> _setCounts = {};
  final Set<String> _loggingExercises = {};
  Timer? _restTimer;
  int _restRemaining = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workout = _loadWorkout();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) unawaited(_syncPending());
    });
  }

  Future<_WorkoutViewData?> _loadWorkout() async {
    final assignment = await _repository.loadClientAssignment();
    if (assignment == null) {
      _stopWatchingWorkout();
      return null;
    }
    _watchWorkout(assignment);
    final sessionId = await _repository.findActiveSession(assignment['id'] as String);
    final counts = sessionId == null ? <String, int>{} : await _repository.loadSetCounts(sessionId);
    return _WorkoutViewData(assignment: assignment, sessionId: sessionId, setCounts: counts);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncPending());
  }

  void _watchWorkout(Map<String, dynamic> assignment) {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final clientId = assignment['client_id'] as String;
    final planId = assignment['plan_id'] as String;
    final key = '$clientId:$planId';
    if (_watchedPlan == key) return;
    _stopWatchingWorkout();
    _watchedPlan = key;
    final client = Supabase.instance.client;
    void refresh(PostgresChangePayload _) {
      if (mounted) setState(() => _workout = _loadWorkout());
    }

    _workoutChannel = client
        .channel('client-workout-$userId-$planId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workout_assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'client_id',
            value: clientId,
          ),
          callback: refresh,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workout_plans',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: planId,
          ),
          callback: refresh,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workout_plan_exercises',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'plan_id',
            value: planId,
          ),
          callback: refresh,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'exercise_library',
          callback: refresh,
        )
        .subscribe();
  }

  void _stopWatchingWorkout() {
    final channel = _workoutChannel;
    _workoutChannel = null;
    _watchedPlan = null;
    if (channel != null) unawaited(channel.unsubscribe().then<void>((_) {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _stopWatchingWorkout();
    _restTimer?.cancel();
    super.dispose();
  }

  Future<void> _startWorkout(Map<String, dynamic> assignment) async {
    try {
      final offline = await _repository.isOffline();
      final sessionId = await _repository.startSession(
        assignmentId: assignment['id'] as String,
        clientId: assignment['client_id'] as String,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _setCounts.clear();
      });
      if (offline) _message('Workout started offline. Your logs will sync when connection returns.');
    } on PostgrestException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Could not start the workout. Check your connection and retry.');
    }
  }

  Future<void> _logSet(Map<String, dynamic> exercise, int currentSet, String sessionId) async {
    final exerciseId = exercise['id'] as String;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _LogSetDialog(repsTarget: exercise['reps'] as String),
    );
    if (result == null || !mounted) return;
    setState(() => _loggingExercises.add(exerciseId));
    try {
      final synced = await _repository.saveSet(
        sessionId: sessionId,
        planExerciseId: exerciseId,
        setNumber: currentSet + 1,
        reps: result['reps'] as int,
        weightKg: result['weight_kg'] as double,
      );
      if (!mounted) return;
      setState(() => _setCounts[exerciseId] = currentSet + 1);
      final restSeconds = exercise['rest_seconds'] as int;
      if (restSeconds > 0) _startRestTimer(restSeconds);
      if (!synced) {
        _message('Set saved securely on this device. It will sync automatically.');
      } else {
        _message('Set ${currentSet + 1} saved.');
      }
    } on PostgrestException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Could not save this set. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _loggingExercises.remove(exerciseId));
    }
  }

  Future<void> _completeWorkout(String sessionId) async {
    try {
      final offline = await _repository.isOffline();
      await _repository.completeSession(sessionId);
      if (!mounted) return;
      _restTimer?.cancel();
      setState(() {
        _sessionId = null;
        _setCounts.clear();
        _restRemaining = 0;
        _workout = _loadWorkout();
      });
      _message(offline ? 'Workout completed offline. It will sync when connection returns.' : 'Workout completed.');
    } on PostgrestException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Could not complete the workout. Check your connection and retry.');
    }
  }

  void _startRestTimer(int seconds) {
    _restTimer?.cancel();
    setState(() => _restRemaining = seconds);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_restRemaining <= 1) {
        timer.cancel();
        if (mounted) setState(() => _restRemaining = 0);
      } else if (mounted) {
        setState(() => _restRemaining--);
      }
    });
  }

  Future<void> _syncPending() async {
    try {
      final result = await _repository.syncPending();
      if (!mounted || result.busy) return;
      if (result.offline) {
        _message('Still offline. Your workout data remains saved securely on this device.');
      } else if (result.error != null) {
        _message('${result.error} Pending workout data remains saved and will retry.');
      } else if (result.syncedCount > 0) {
        _message('${result.syncedCount} offline workout item${result.syncedCount == 1 ? '' : 's'} synced.');
      }
    } catch (_) {
      if (mounted) _message('Sync could not start. Your workout data remains saved securely on this device.');
    }
  }

  Future<void> _openDemo(String url) async {
    try {
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && mounted) _message('This demo link could not be opened.');
    } catch (_) {
      if (mounted) _message('This demo link could not be opened.');
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Today\'s workout'),
          actions: [
            IconButton(
              tooltip: 'Sync pending workout logs',
              onPressed: _syncPending,
              icon: const Icon(Icons.sync),
            ),
          ],
        ),
        body: FutureBuilder<_WorkoutViewData?>(
          future: _workout,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _WorkoutMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Workout could not be loaded',
                message: 'Check your connection and retry. Previously saved offline logs remain on this device.',
                action: TextButton.icon(
                  onPressed: () => setState(() => _workout = _loadWorkout()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const _WorkoutMessage(
                icon: Icons.fitness_center,
                title: 'No workout assigned',
                message: 'Your trainer’s assigned workout will appear here.',
              );
            }
            final plan = data.assignment['workout_plans'] as Map<String, dynamic>;
            final exercises = List<Map<String, dynamic>>.from(plan['workout_plan_exercises'] as List? ?? [])
              ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
            final sessionId = _sessionId ?? data.sessionId;
            final counts = {...data.setCounts, ..._setCounts};
            return RefreshIndicator(
              onRefresh: () async => setState(() => _workout = _loadWorkout()),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(plan['name'] as String, style: Theme.of(context).textTheme.headlineSmall),
                  if ((plan['description'] as String).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(plan['description'] as String),
                  ],
                  const SizedBox(height: 16),
                  if (_restRemaining > 0) _restCard(),
                  if (exercises.isEmpty)
                    const _WorkoutMessage(
                      icon: Icons.playlist_remove,
                      title: 'This plan has no exercises',
                      message: 'Ask your trainer to update your plan.',
                    )
                  else ...exercises.map((item) => _exerciseCard(item, counts[item['id']] ?? 0, sessionId)),
                  const SizedBox(height: 12),
                  if (sessionId == null)
                    FilledButton.icon(
                      onPressed: exercises.isEmpty ? null : () => _startWorkout(data.assignment),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start workout'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => _completeWorkout(sessionId),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Complete workout'),
                    ),
                ],
              ),
            );
          },
        ),
      );

  Widget _exerciseCard(Map<String, dynamic> item, int completedSets, String? sessionId) {
    final exercise = item['exercise_library'] as Map<String, dynamic>;
    final totalSets = item['sets'] as int;
    final exerciseId = item['id'] as String;
    final mediaUrl = exercise['media_url'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(exercise['name'] as String, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('$totalSets sets x ${item['reps']} reps  |  ${item['rest_seconds']} sec rest'),
          if ((exercise['instructions'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(exercise['instructions'] as String),
          ],
          if ((item['notes'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(item['notes'] as String, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _openDemo(mediaUrl),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Open exercise demo'),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('$completedSets of $totalSets sets logged')),
            FilledButton.tonal(
              onPressed: sessionId == null || completedSets >= totalSets || _loggingExercises.contains(exerciseId)
                  ? null
                  : () => _logSet(item, completedSets, sessionId),
              child: _loggingExercises.contains(exerciseId)
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Log set'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _restCard() => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text('Rest  ${_formatDuration(_restRemaining)}'),
          trailing: IconButton(
            tooltip: 'Skip rest timer',
            onPressed: () {
              _restTimer?.cancel();
              setState(() => _restRemaining = 0);
            },
            icon: const Icon(Icons.skip_next),
          ),
        ),
      );

  String _formatDuration(int seconds) => '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _WorkoutViewData {
  const _WorkoutViewData({required this.assignment, required this.sessionId, required this.setCounts});

  final Map<String, dynamic> assignment;
  final String? sessionId;
  final Map<String, int> setCounts;
}

class _LogSetDialog extends StatefulWidget {
  const _LogSetDialog({required this.repsTarget});

  final String repsTarget;

  @override
  State<_LogSetDialog> createState() => _LogSetDialogState();
}

class _LogSetDialogState extends State<_LogSetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _reps = TextEditingController(text: RegExp(r'\d+').firstMatch(widget.repsTarget)?.group(0) ?? '8');
  final _weight = TextEditingController(text: '0');

  @override
  void dispose() {
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  String? _validateReps(String? value) {
    final reps = int.tryParse(value?.trim() ?? '');
    return reps == null || reps < 0 || reps > 1000 ? 'Enter reps between 0 and 1000.' : null;
  }

  String? _validateWeight(String? value) {
    final weight = double.tryParse(value?.trim() ?? '');
    return weight == null || weight < 0 || weight > 9999.99 ? 'Enter weight between 0 and 9999.99 kg.' : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Log completed set'),
        content: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _reps,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reps completed'),
              validator: _validateReps,
            ),
            TextFormField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (kg)'),
              validator: _validateWeight,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context, {
                'reps': int.parse(_reps.text.trim()),
                'weight_kg': double.parse(_weight.text.trim()),
              });
            },
            child: const Text('Save set'),
          ),
        ],
      );
}

class _WorkoutMessage extends StatelessWidget {
  const _WorkoutMessage({required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ]),
        ),
      );
}