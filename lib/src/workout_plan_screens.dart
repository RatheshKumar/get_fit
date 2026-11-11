import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'workout_repository.dart';

class WorkoutPlanLibraryScreen extends StatefulWidget {
  const WorkoutPlanLibraryScreen({super.key});

  @override
  State<WorkoutPlanLibraryScreen> createState() => _WorkoutPlanLibraryScreenState();
}

class _WorkoutPlanLibraryScreenState extends State<WorkoutPlanLibraryScreen> {
  final _repository = WorkoutRepository(Supabase.instance.client);
  late Future<List<Map<String, dynamic>>> _plans;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _plans = _repository.loadPlans();
  }

  Future<void> _createPlan() async {
    final draft = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _PlanDraftDialog(),
    );
    if (draft == null || !mounted) return;
    await _saveExercise(draft);
  }

  Future<void> _saveExercise(Map<String, dynamic> draft) async {
    setState(() => _saving = true);
    try {
      final id = await _repository.createPlan(name: draft['name']!, description: draft['description']!);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WorkoutPlanEditorScreen(planId: id, planName: draft['name']!),
      ));
      if (mounted) setState(() => _plans = _repository.loadPlans());
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('Could not create the plan. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Workout plans')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _saving ? null : _createPlan,
          icon: const Icon(Icons.add),
          label: const Text('New plan'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _plans,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _PlanMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Plans could not be loaded',
                message: 'Check your connection and try again.',
                action: TextButton.icon(
                  onPressed: () => setState(() => _plans = _repository.loadPlans()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              );
            }
            final plans = snapshot.data ?? [];
            if (plans.isEmpty) {
              return const _PlanMessage(
                icon: Icons.fitness_center,
                title: 'No workout plans yet',
                message: 'Create a plan and add exercises to build your library.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => setState(() => _plans = _repository.loadPlans()),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: plans.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final plan = plans[index];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.fitness_center)),
                      title: Text(plan['name'] as String),
                      subtitle: Text((plan['description'] as String).isEmpty
                          ? 'No description'
                          : plan['description'] as String),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => WorkoutPlanEditorScreen(
                          planId: plan['id'] as String,
                          planName: plan['name'] as String,
                        ),
                      )),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
}

class WorkoutPlanEditorScreen extends StatefulWidget {
  const WorkoutPlanEditorScreen({required this.planId, required this.planName, super.key});

  final String planId;
  final String planName;

  @override
  State<WorkoutPlanEditorScreen> createState() => _WorkoutPlanEditorScreenState();
}

class _WorkoutPlanEditorScreenState extends State<WorkoutPlanEditorScreen> {
  final _repository = WorkoutRepository(Supabase.instance.client);
  late Future<List<Map<String, dynamic>>> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = _repository.loadPlanExercises(widget.planId);
  }

  Future<void> _addExercise(List<Map<String, dynamic>> current) async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _PlanExerciseDialog(initial: null),
    );
    if (draft == null || !mounted) return;
    await _saveExercise(current, draft);
  }

  Future<void> _saveExercise(List<Map<String, dynamic>> current, Map<String, dynamic> draft) async {
    setState(() => _saving = true);
    try {
      final itemId = draft['id'] as String?;
      if (itemId == null) {
        final nextPosition = current.fold<int>(0, (max, item) =>
            (item['position'] as int) > max ? item['position'] as int : max) + 1;
        await _repository.addPlanExercise(
          planId: widget.planId,
          exerciseId: draft['exercise_id'] as String,
          position: nextPosition,
          sets: draft['sets'] as int,
          reps: draft['reps'] as String,
          restSeconds: draft['rest_seconds'] as int,
          notes: draft['notes'] as String,
        );
      } else {
        await _repository.updatePlanExercise(
          itemId: itemId,
          exerciseId: draft['exercise_id'] as String,
          sets: draft['sets'] as int,
          reps: draft['reps'] as String,
          restSeconds: draft['rest_seconds'] as int,
          notes: draft['notes'] as String,
        );
      }
      if (mounted) setState(() => _items = _repository.loadPlanExercises(widget.planId));
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('Could not save this exercise. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeExercise(String id) async {
    try {
      await Supabase.instance.client.from('workout_plan_exercises').delete().eq('id', id);
      if (mounted) setState(() => _items = _repository.loadPlanExercises(widget.planId));
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('Could not remove this exercise. Check your connection and retry.');
    }
  }

  Future<void> _editExercise(Map<String, dynamic> item) async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _PlanExerciseDialog(initial: item),
    );
    if (draft != null && mounted) {
      final snapshot = await _items;
      if (mounted) await _saveExercise(snapshot, draft);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.planName)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _saving ? null : () async {
            final snapshot = await _items;
            if (mounted) await _addExercise(snapshot);
          },
          icon: const Icon(Icons.add),
          label: const Text('Add exercise'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _items,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _PlanMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Plan exercises could not be loaded',
                message: 'Check your connection and try again.',
                action: TextButton.icon(
                  onPressed: () => setState(() => _items = _repository.loadPlanExercises(widget.planId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return const _PlanMessage(
                icon: Icons.playlist_add,
                title: 'This plan has no exercises',
                message: 'Add an exercise with a target number of sets and reps.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => setState(() => _items = _repository.loadPlanExercises(widget.planId)),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final exercise = item['exercise_library'] as Map<String, dynamic>;
                  return Card(
                    child: ListTile(
                      title: Text(exercise['name'] as String),
                      subtitle: Text('${item['sets']} sets x ${item['reps']} reps  |  ${item['rest_seconds']} sec rest'),
                      onTap: _saving ? null : () => _editExercise(item),
                      trailing: IconButton(
                        tooltip: 'Remove from plan',
                        onPressed: () => _removeExercise(item['id'] as String),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
}

class AssignWorkoutScreen extends StatefulWidget {
  const AssignWorkoutScreen({required this.clientId, required this.clientName, super.key});

  final String clientId;
  final String clientName;

  @override
  State<AssignWorkoutScreen> createState() => _AssignWorkoutScreenState();
}

class _AssignWorkoutScreenState extends State<AssignWorkoutScreen> {
  final _repository = WorkoutRepository(Supabase.instance.client);
  late Future<List<Map<String, dynamic>>> _plans;
  String? _selectedPlan;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _plans = _repository.loadPlans();
  }

  Future<void> _assign() async {
    final planId = _selectedPlan;
    if (planId == null) return;
    setState(() => _saving = true);
    try {
      await _repository.assignPlan(clientId: widget.clientId, planId: planId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Workout plan assigned.')));
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('Could not assign this plan. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Assign to ${widget.clientName}')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _plans,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _PlanMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Plans could not be loaded',
                message: 'Check your connection and try again.',
                action: TextButton.icon(
                  onPressed: () => setState(() => _plans = _repository.loadPlans()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              );
            }
            final plans = snapshot.data ?? [];
            if (plans.isEmpty) {
              return const _PlanMessage(
                icon: Icons.fitness_center,
                title: 'Create a workout plan first',
                message: 'Your saved plans will appear here for assignment.',
              );
            }
            return Column(children: [
              Expanded(
                child: RadioGroup<String>(
                  groupValue: _selectedPlan,
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedPlan = value);
                  },
                  child: ListView.builder(
                    itemCount: plans.length,
                    itemBuilder: (context, index) {
                      final plan = plans[index];
                      return RadioListTile<String>(
                        value: plan['id'] as String,
                        title: Text(plan['name'] as String),
                        subtitle: Text(plan['description'] as String),
                      );
                    },
                  ),
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selectedPlan == null || _saving ? null : _assign,
                    child: _saving ? const CircularProgressIndicator() : const Text('Assign plan'),
                  ),
                ),
              ),
            ]);
          },
        ),
      );
}

class _PlanDraftDialog extends StatefulWidget {
  const _PlanDraftDialog();

  @override
  State<_PlanDraftDialog> createState() => _PlanDraftDialogState();
}

class _PlanDraftDialogState extends State<_PlanDraftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New workout plan'),
        content: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Plan name'),
              validator: (value) => (value?.trim().isEmpty ?? true) ? 'Enter a plan name.' : null,
            ),
            TextFormField(
              controller: _description,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context, {'name': _name.text.trim(), 'description': _description.text.trim()});
            },
            child: const Text('Create'),
          ),
        ],
      );
}

class _PlanExerciseDialog extends StatefulWidget {
  const _PlanExerciseDialog({required this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_PlanExerciseDialog> createState() => _PlanExerciseDialogState();
}

class _PlanExerciseDialogState extends State<_PlanExerciseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _repository = WorkoutRepository(Supabase.instance.client);
  late final _sets = TextEditingController(text: '${widget.initial?['sets'] ?? 3}');
  late final _reps = TextEditingController(text: '${widget.initial?['reps'] ?? '8-12'}');
  late final _rest = TextEditingController(text: '${widget.initial?['rest_seconds'] ?? 60}');
  late final _notes = TextEditingController(text: widget.initial?['notes'] as String? ?? '');
  late Future<List<Map<String, dynamic>>> _exercises;
  String? _exerciseId;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _exercises = _repository.loadExercises();
    _exerciseId = widget.initial?['exercise_id'] as String?;
  }

  @override
  void dispose() {
    _sets.dispose();
    _reps.dispose();
    _rest.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _createExercise() async {
    final draft = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _ExerciseDraftDialog(),
    );
    if (draft == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final id = await _repository.createExercise(
        name: draft['name']!,
        instructions: draft['instructions']!,
        mediaUrl: draft['media_url'],
      );
      if (mounted) {
        setState(() {
          _exerciseId = id;
          _exercises = _repository.loadExercises();
        });
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save this exercise. Check your connection and retry.')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String? _validateNumber(String? value, {required int min, required int max, required String label}) {
    final number = int.tryParse(value?.trim() ?? '');
    if (number == null || number < min || number > max) return '$label must be between $min and $max.';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate() || _exerciseId == null) return;
    Navigator.pop(context, {
      'id': widget.initial?['id'],
      'exercise_id': _exerciseId,
      'sets': int.parse(_sets.text.trim()),
      'reps': _reps.text.trim(),
      'rest_seconds': int.parse(_rest.text.trim()),
      'notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add exercise'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _exercises,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                    if (snapshot.hasError) return const Text('Exercise library could not be loaded. Close and retry.');
                    final exercises = snapshot.data ?? [];
                    if (exercises.isEmpty) return const Text('Create an exercise to start your library.');
                    final ids = exercises.map((exercise) => exercise['id'] as String).toSet();
                    final selected = ids.contains(_exerciseId) ? _exerciseId : null;
                    return DropdownButtonFormField<String>(
                      initialValue: selected,
                      items: exercises.map((exercise) => DropdownMenuItem(
                        value: exercise['id'] as String,
                        child: Text(exercise['name'] as String, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (value) => setState(() => _exerciseId = value),
                      decoration: const InputDecoration(labelText: 'Exercise'),
                      validator: (value) => value == null ? 'Choose an exercise.' : null,
                    );
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _creating ? null : _createExercise,
                    icon: const Icon(Icons.add),
                    label: const Text('Create exercise'),
                  ),
                ),
                TextFormField(
                  controller: _sets,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sets'),
                  validator: (value) => _validateNumber(value, min: 1, max: 50, label: 'Sets'),
                ),
                TextFormField(
                  controller: _reps,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Reps or range'),
                  validator: (value) => (value?.trim().isEmpty ?? true) ? 'Enter a rep target.' : null,
                ),
                TextFormField(
                  controller: _rest,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Rest (seconds)'),
                  validator: (value) => _validateNumber(value, min: 0, max: 3600, label: 'Rest'),
                ),
                TextFormField(controller: _notes, maxLength: 500, decoration: const InputDecoration(labelText: 'Coaching note (optional)')),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _creating ? null : _submit, child: const Text('Add to plan')),
        ],
      );
}

class _ExerciseDraftDialog extends StatefulWidget {
  const _ExerciseDraftDialog();

  @override
  State<_ExerciseDraftDialog> createState() => _ExerciseDraftDialogState();
}

class _ExerciseDraftDialogState extends State<_ExerciseDraftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _instructions = TextEditingController();
  final _mediaUrl = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    _mediaUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create exercise'),
        content: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Exercise name'),
              validator: (value) => (value?.trim().isEmpty ?? true) ? 'Enter an exercise name.' : null,
            ),
            TextFormField(controller: _instructions, maxLength: 1000, maxLines: 3, decoration: const InputDecoration(labelText: 'Instructions (optional)')),
            TextFormField(
              controller: _mediaUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Demo image/video URL (optional)'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final uri = Uri.tryParse(value.trim());
                return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty
                    ? null
                    : 'Enter a valid http or https URL.';
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'instructions': _instructions.text.trim(),
                'media_url': _mediaUrl.text.trim(),
              });
            },
            child: const Text('Save exercise'),
          ),
        ],
      );
}

class _PlanMessage extends StatelessWidget {
  const _PlanMessage({required this.icon, required this.title, required this.message, this.action});

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