import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'workout_plan_screens.dart';

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({required this.trainerName, super.key});

  final String trainerName;

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  final _searchController = TextEditingController();
  String _statusFilter = 'all';
  String _search = '';
  late Stream<List<Map<String, dynamic>>> _clients;

  @override
  void initState() {
    super.initState();
    _clients = Supabase.instance.client
        .from('clients')
        .stream(primaryKey: ['id'])
        .eq('trainer_id', Supabase.instance.client.auth.currentUser!.id)
        .order('full_name');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _inviteClient() async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _InviteClientDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      await Supabase.instance.client.functions.invoke('invite-client', body: draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation sent.')),
        );
      }
    } on FunctionException catch (error) {
      if (mounted) _showError(error.details?.toString() ?? 'Could not invite this client.');
    } catch (_) {
      if (mounted) _showError('Could not send the invitation. Check your connection and retry.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('Clients', style: Theme.of(context).textTheme.titleLarge),
          actions: [
            IconButton(
              tooltip: 'Workout plans',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const WorkoutPlanLibraryScreen(),
              )),
              icon: const Icon(Icons.fitness_center),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _inviteClient,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add client'),
        ),
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Welcome, ${widget.trainerName}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _search = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search clients',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'active', label: Text('Active')),
                    ButtonSegment(value: 'paused', label: Text('Paused')),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (selection) => setState(() => _statusFilter = selection.first),
                ),
              ]),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _clients,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _MessageState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Clients could not be loaded',
                      message: 'Check your connection, then try again.',
                      action: TextButton.icon(
                        onPressed: () => setState(() => _clients = Supabase.instance.client
                            .from('clients')
                            .stream(primaryKey: ['id'])
                            .eq('trainer_id', Supabase.instance.client.auth.currentUser!.id)
                            .order('full_name')),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    );
                  }
                  final records = (snapshot.data ?? []).where((client) {
                    final matchesStatus = _statusFilter == 'all' || client['status'] == _statusFilter;
                    final matchesSearch = (client['full_name'] as String).toLowerCase().contains(_search) ||
                        (client['email'] as String? ?? '').toLowerCase().contains(_search) ||
                        (client['goal'] as String).toLowerCase().contains(_search);
                    return matchesStatus && matchesSearch;
                  }).toList();
                  if (records.isEmpty) {
                    final hasClients = (snapshot.data ?? []).isNotEmpty;
                    return _MessageState(
                      icon: hasClients ? Icons.search_off : Icons.people_outline,
                      title: hasClients ? 'No matching clients' : 'Your client list is empty',
                      message: hasClients ? 'Try another search or filter.' : 'Add a client to get started.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() => _clients = Supabase.instance.client
                          .from('clients')
                          .stream(primaryKey: ['id'])
                          .eq('trainer_id', Supabase.instance.client.auth.currentUser!.id)
                          .order('full_name'));
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: records.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _ClientTile(client: records[index]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      );
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.client});

  final Map<String, dynamic> client;

  @override
  Widget build(BuildContext context) {
    final active = client['status'] == 'active';
    final name = client['full_name'] as String;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(child: Text(name.substring(0, 1).toUpperCase())),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(client['goal'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(active ? Icons.chevron_right : Icons.pause_circle_outline),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ClientProfileScreen(client: client),
        )),
      ),
    );
  }
}

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({required this.client, super.key});

  final Map<String, dynamic> client;

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  late Map<String, dynamic> _client = widget.client;
  late Future<String> _notes = _loadNotes();
  bool _busy = false;

  Future<String> _loadNotes() async {
    final result = await Supabase.instance.client
        .from('client_private_notes')
        .select('notes')
        .eq('client_id', _client['id'])
        .maybeSingle();
    return result?['notes'] as String? ?? '';
  }

  Future<void> _editClient() async {
    String notes;
    try {
      notes = await _notes;
    } catch (_) {
      if (mounted) _showMessage('Private notes could not be loaded. Check your connection and retry.');
      return;
    }
    if (!mounted) return;
    final updates = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditClientDialog(client: _client, notes: notes),
    );
    if (updates == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final privateNotes = updates.remove('private_notes') as String;
      await Supabase.instance.client.from('clients').update(updates).eq('id', _client['id']);
      await Supabase.instance.client.from('client_private_notes').upsert({
        'client_id': _client['id'],
        'trainer_id': Supabase.instance.client.auth.currentUser!.id,
        'notes': privateNotes,
      });
      if (mounted) {
        setState(() {
          _client = {..._client, ...updates};
          _notes = Future.value(privateNotes);
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not save all profile changes. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleStatus() async {
    setState(() => _busy = true);
    final nextStatus = _client['status'] == 'active' ? 'paused' : 'active';
    try {
      await Supabase.instance.client.from('clients').update({'status': nextStatus}).eq('id', _client['id']);
      if (mounted) setState(() => _client = {..._client, 'status': nextStatus});
    } on PostgrestException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not update this client. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteClient() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete client account?'),
        content: const Text('This permanently deletes the client login and their profile. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.functions.invoke(
        'delete-client',
        body: {'client_id': _client['id']},
      );
      if (mounted) Navigator.of(context).pop();
    } on FunctionException catch (error) {
      if (mounted) _showMessage(error.details?.toString() ?? 'Could not delete this client.');
    } catch (_) {
      if (mounted) _showMessage('Could not delete this client. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_client['full_name'] as String)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Client details', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  _DetailRow(label: 'Goal', value: _client['goal'] as String),
                  _DetailRow(label: 'Email', value: _client['email'] as String? ?? 'Not provided'),
                  _DetailRow(label: 'Phone', value: _client['phone'] as String? ?? 'Not provided'),
                  _DetailRow(label: 'Status', value: _client['status'] as String),
                  _DetailRow(label: 'Starting weight', value: _weight(_client['starting_weight_kg'])),
                  _DetailRow(label: 'Current weight', value: _weight(_client['current_weight_kg'])),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<String>(
              future: _notes,
              builder: (context, snapshot) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Private trainer notes', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const LinearProgressIndicator()
                    else if (snapshot.hasError)
                      const Text('Notes could not be loaded. Try reopening this profile.')
                    else
                      Text(snapshot.data!.isEmpty ? 'No private notes yet.' : snapshot.data!),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _editClient,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit client details'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => AssignWorkoutScreen(
                          clientId: _client['id'] as String,
                          clientName: _client['full_name'] as String,
                        ),
                      )),
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('Assign workout plan'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _toggleStatus,
              icon: Icon(_client['status'] == 'active' ? Icons.pause : Icons.play_arrow),
              label: Text(_client['status'] == 'active' ? 'Pause client' : 'Resume client'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _deleteClient,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete client account'),
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );

  String _weight(dynamic value) => value == null ? 'Not recorded' : '${value.toString()} kg';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 132, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(child: Text(value)),
        ]),
      );
}

class _EditClientDialog extends StatefulWidget {
  const _EditClientDialog({required this.client, required this.notes});

  final Map<String, dynamic> client;
  final String notes;

  @override
  State<_EditClientDialog> createState() => _EditClientDialogState();
}

class _EditClientDialogState extends State<_EditClientDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.client['full_name'] as String);
  late final _goal = TextEditingController(text: widget.client['goal'] as String);
  late final _phone = TextEditingController(text: widget.client['phone'] as String? ?? '');
  late final _weight = TextEditingController(text: widget.client['current_weight_kg']?.toString() ?? '');
  late final _notes = TextEditingController(text: widget.notes);

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    _phone.dispose();
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _validateRequired(String? value, String label, int limit) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter $label.';
    if (text.length > limit) return '$label must be $limit characters or fewer.';
    return null;
  }

  String? _validateWeight(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    final parsed = double.tryParse(value!.trim());
    if (parsed == null || parsed <= 0 || parsed > 999.99) return 'Enter a weight between 0 and 999.99 kg.';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'full_name': _name.text.trim(),
      'goal': _goal.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'current_weight_kg': _weight.text.trim().isEmpty ? null : double.parse(_weight.text.trim()),
      'private_notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit client'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: _name, maxLength: 120, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => _validateRequired(v, 'a name', 120)),
                TextFormField(controller: _goal, maxLength: 500, maxLines: 2, decoration: const InputDecoration(labelText: 'Goal'), validator: (v) => _validateRequired(v, 'a goal', 500)),
                TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
                TextFormField(controller: _weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Current weight (kg, optional)'), validator: _validateWeight),
                TextFormField(controller: _notes, maxLines: 4, decoration: const InputDecoration(labelText: 'Private trainer notes')),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save changes')),
        ],
      );
}

class _InviteClientDialog extends StatefulWidget {
  const _InviteClientDialog();

  @override
  State<_InviteClientDialog> createState() => _InviteClientDialogState();
}

class _InviteClientDialogState extends State<_InviteClientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _goal = TextEditingController();
  final _weight = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _goal.dispose();
    _weight.dispose();
    super.dispose();
  }

  String? _required(String? value, String label, int limit) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter $label.';
    if (text.length > limit) return '$label must be $limit characters or fewer.';
    return null;
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) return 'Enter a valid email address.';
    return null;
  }

  String? _validateWeight(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    final weight = double.tryParse(value!.trim());
    if (weight == null || weight <= 0 || weight > 999.99) return 'Enter a weight between 0 and 999.99 kg.';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'full_name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'goal': _goal.text.trim(),
      'starting_weight_kg': _weight.text.trim().isEmpty ? null : double.parse(_weight.text.trim()),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Invite a client'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: _name, maxLength: 120, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => _required(v, 'a name', 120)),
                TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email for invitation'), validator: _validateEmail),
                TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
                TextFormField(controller: _goal, maxLength: 500, maxLines: 2, decoration: const InputDecoration(labelText: 'Primary goal'), validator: (v) => _required(v, 'a goal', 500)),
                TextFormField(controller: _weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Starting weight (kg, optional)'), validator: _validateWeight),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Send invitation')),
        ],
      );
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.title, required this.message, this.action});

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