import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'client_workout_screen.dart';

const _ink = Color(0xff14213d);
const _blue = Color(0xff2458dc);
const _surface = Color(0xfff4f7fc);

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  late Stream<List<Map<String, dynamic>>> _clientRecord;
  int _tab = 0;
  String? _assignmentClientId;
  Future<Map<String, dynamic>?>? _assignment;
  String? _metricsClientId;
  Stream<List<Map<String, dynamic>>>? _metrics;

  Stream<List<Map<String, dynamic>>> _watchRecord() => Supabase.instance.client
      .from('clients')
      .stream(primaryKey: ['id'])
      .eq('profile_id', Supabase.instance.client.auth.currentUser!.id)
      .limit(1);

  @override
  void initState() {
    super.initState();
    _clientRecord = _watchRecord();
  }

  Future<Map<String, dynamic>?> _loadAssignment(String clientId) => Supabase.instance.client
      .from('workout_assignments')
      .select('id, starts_on, workout_plans(name, description)')
      .eq('client_id', clientId)
      .eq('is_active', true)
      .maybeSingle();

  Stream<List<Map<String, dynamic>>> _watchMetrics(String clientId) => Supabase.instance.client
      .from('body_metrics')
      .stream(primaryKey: ['id'])
      .eq('client_id', clientId)
      .order('log_date');

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _surface,
        appBar: _tab == 1 ? null : AppBar(
          title: Text(_tab == 0 ? 'My day' : _tab == 1 ? 'Training' : _tab == 2 ? 'My progress' : 'My profile'),
          actions: [
            if (_tab != 3)
              IconButton(
                tooltip: 'Profile and sign out',
                onPressed: () => setState(() => _tab = 3),
                icon: const Icon(Icons.account_circle_outlined),
              ),
          ],
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _clientRecord,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _StateMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load your coaching space',
                message: 'Check your connection and try again.',
                action: TextButton.icon(
                  onPressed: () => setState(() => _clientRecord = _watchRecord()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              );
            }
            final records = snapshot.data ?? [];
            if (records.isEmpty) {
              return const _StateMessage(
                icon: Icons.person_search_outlined,
                title: 'Your account is not linked yet',
                message: 'Ask your trainer to finish setting up your client account.',
              );
            }
            final client = records.first;
            if (_assignmentClientId != client['id']) {
              _assignmentClientId = client['id'] as String;
              _assignment = _loadAssignment(_assignmentClientId!);
            }
            if (_metricsClientId != client['id']) {
              _metricsClientId = client['id'] as String;
              _metrics = _watchMetrics(_metricsClientId!);
            }
            return _tab == 1
                ? const ClientWorkoutScreen()
                : _tab == 2
                    ? _progress(client)
                    : _tab == 3
                        ? _profile(client)
                        : _today(client);
          },
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Workouts'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      );

  Widget _today(Map<String, dynamic> client) {
    final status = client['status'] as String? ?? 'active';
    final name = (client['full_name'] as String? ?? 'there').split(' ').first;
    return RefreshIndicator(
      onRefresh: () async => setState(() {
        _clientRecord = _watchRecord();
        _assignment = _loadAssignment(client['id'] as String);
      }),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Text(_greeting(), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xff66738b))),
          const SizedBox(height: 4),
          Text('Let’s get stronger, $name.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: _ink, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          _planCard(client, status),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _metricCard('Starting weight', _weight(client['starting_weight_kg']), Icons.flag_outlined)),
            const SizedBox(width: 12),
            Expanded(child: _latestWeightCard(client)),
          ]),
          const SizedBox(height: 20),
          Text('Your coaching focus', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xffe9efff), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.track_changes, color: _blue)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your current goal', style: TextStyle(color: Color(0xff76829a), fontSize: 13)),
                  const SizedBox(height: 5),
                  Text(client['goal'] as String? ?? 'Your trainer will add a goal soon.', style: const TextStyle(color: _ink, fontSize: 16, height: 1.4, fontWeight: FontWeight.w600)),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Text('Quick actions', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _ink, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _quickAction(Icons.fitness_center, 'Open workout', () => setState(() => _tab = 1))),
            const SizedBox(width: 12),
            Expanded(child: _quickAction(Icons.add_chart, 'Log weight', () => setState(() => _tab = 2))),
          ]),
        ],
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> client, String status) => FutureBuilder<Map<String, dynamic>?>(
        future: _assignment,
        builder: (context, snapshot) {
          final assignment = snapshot.data;
          final plan = assignment?['workout_plans'] as Map<String, dynamic>?;
          final paused = status != 'active';
          return Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xff173caa), Color(0xff3978ed)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: const Color(0xff2458dc).withOpacity(.2), blurRadius: 24, offset: const Offset(0, 12))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('TODAY’S PLAN', style: TextStyle(color: Color(0xffd4e2ff), letterSpacing: 1.2, fontSize: 12, fontWeight: FontWeight.w700))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(30)), child: Text(paused ? 'PAUSED' : 'READY', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 19),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(color: Colors.white, backgroundColor: Color(0x445c8cec))
              else if (snapshot.hasError)
                const Text('Your plan could not load. Pull down to retry.', style: TextStyle(color: Colors.white))
              else if (paused)
                const Text('Training is paused', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w700))
              else if (plan == null)
                const Text('Your trainer is building your plan', style: TextStyle(color: Colors.white, fontSize: 22, height: 1.2, fontWeight: FontWeight.w700))
              else
                Text(plan['name'] as String? ?? 'Your workout', style: const TextStyle(color: Colors.white, fontSize: 25, height: 1.15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(paused ? 'Contact your coach if you have questions.' : plan?['description'] as String? ?? 'Your next workout is ready when you are.', style: const TextStyle(color: Color(0xffdce8ff), height: 1.4)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: paused || plan == null ? null : () => setState(() => _tab = 1),
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _blue, disabledBackgroundColor: Colors.white.withOpacity(.35), disabledForegroundColor: Colors.white),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(plan == null ? Icons.hourglass_empty : Icons.play_arrow_rounded), const SizedBox(width: 7), Text(paused ? 'Training paused' : plan == null ? 'Waiting for plan' : 'Start workout', style: const TextStyle(fontWeight: FontWeight.w700))]),
                ),
              ),
            ]),
          );
        },
      );

  Widget _progress(Map<String, dynamic> client) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _metrics,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return _StateMessage(icon: Icons.cloud_off_outlined, title: 'Progress could not load', message: 'Check your connection and try again.', action: TextButton(onPressed: () => setState(() => _metrics = _watchMetrics(client['id'] as String)), child: const Text('Retry')));
          final entries = snapshot.data ?? [];
          final initial = (client['starting_weight_kg'] as num?)?.toDouble();
          final latest = entries.isEmpty ? (client['current_weight_kg'] as num?)?.toDouble() : (entries.last['weight'] as num?)?.toDouble();
          final delta = initial == null || latest == null ? null : latest - initial;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
            children: [
              Text('Small steps add up.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: _ink, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Your trainer can follow every update you log.', style: TextStyle(color: Color(0xff6e7a91))),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: _metricCard('Current', latest == null ? 'Not logged' : '${latest.toStringAsFixed(1)} kg', Icons.monitor_weight_outlined)),
                const SizedBox(width: 12),
                Expanded(child: _metricCard('Change', delta == null ? '—' : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg', Icons.show_chart)),
              ]),
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: () => _logWeight(client), icon: const Icon(Icons.add), label: const Text('Log today’s weight')),
              const SizedBox(height: 22),
              Text('Weight history', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _ink, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [Icon(Icons.insights_outlined, size: 34, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 8), const Text('Your first check-in starts here', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 4), const Text('Log your weight to build a progress history.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff6e7a91)))])))
              else
                ...entries.reversed.map((entry) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xffe9efff), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.monitor_weight_outlined, color: _blue)),
                        title: Text('${(entry['weight'] as num?)?.toStringAsFixed(1) ?? '—'} kg', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(entry['log_date'] as String? ?? ''),
                      ),
                    )),
            ],
          );
        },
      );

  Widget _latestWeightCard(Map<String, dynamic> client) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _metrics,
        builder: (context, snapshot) {
          final entries = snapshot.data ?? [];
          final value = entries.isEmpty ? client['current_weight_kg'] : entries.last['weight'] ?? client['current_weight_kg'];
          return _metricCard('Current weight', _weight(value), Icons.monitor_weight_outlined);
        },
      );

  Future<void> _logWeight(Map<String, dynamic> client) async {
    final weight = await showDialog<double>(context: context, builder: (_) => const _WeightDialog());
    if (weight == null || !mounted) return;
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      await Supabase.instance.client.from('body_metrics').insert({
        'client_id': client['id'],
        'log_date': today,
        'weight': weight,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Weight saved to your progress.')));
    } on PostgrestException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save your weight. Try again.')));
    }
  }

  Widget _profile(Map<String, dynamic> client) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(children: [
              CircleAvatar(radius: 38, backgroundColor: const Color(0xffe7edff), child: Text((client['full_name'] as String? ?? 'C').substring(0, 1).toUpperCase(), style: const TextStyle(color: _blue, fontSize: 28, fontWeight: FontWeight.w800))),
              const SizedBox(height: 12),
              Text(client['full_name'] as String? ?? 'Client', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _ink, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(client['status'] == 'active' ? 'Training active' : 'Training paused', style: const TextStyle(color: Color(0xff6e7a91))),
            ]),
          ),
          const SizedBox(height: 16),
          _profileItem(Icons.track_changes, 'Training goal', client['goal'] as String? ?? 'Not set'),
          _profileItem(Icons.flag_outlined, 'Starting weight', _weight(client['starting_weight_kg'])),
          _profileItem(Icons.monitor_weight_outlined, 'Current weight', _weight(client['current_weight_kg'])),
          _profileItem(Icons.calendar_today_outlined, 'Member since', _date(client['created_at'] as String?)),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      );

  Widget _profileItem(IconData icon, String title, String value) => Card(
        margin: const EdgeInsets.only(bottom: 9),
        child: ListTile(
          leading: Icon(icon, color: _blue),
          title: Text(title, style: const TextStyle(fontSize: 12, color: Color(0xff76829a))),
          subtitle: Text(value, style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _metricCard(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _blue, size: 21),
          const SizedBox(height: 12),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: Color(0xff76829a), fontSize: 12)),
        ]),
      );

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16), child: Row(children: [Icon(icon, color: _blue), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)))])),
        ),
      );

  String _greeting() {
    final hour = DateTime.now().hour;
    return hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
  }

  String _weight(dynamic value) => value == null ? 'Not recorded' : '${(value as num).toStringAsFixed(1)} kg';
  String _date(String? value) => value == null ? 'Recently' : DateTime.tryParse(value)?.toLocal().toString().split(' ').first ?? 'Recently';
}

class _WeightDialog extends StatefulWidget {
  const _WeightDialog();

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  final _formKey = GlobalKey<FormState>();
  final _weight = TextEditingController();

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Log your weight'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _weight,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Weight in kg', suffixText: 'kg'),
            validator: (value) {
              final number = double.tryParse(value?.trim() ?? '');
              return number == null || number < 1 || number > 1000 ? 'Enter a weight between 1 and 1000 kg.' : null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (_formKey.currentState!.validate()) Navigator.pop(context, double.parse(_weight.text.trim())); }, child: const Text('Save weight')),
        ],
      );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 66, height: 66, decoration: BoxDecoration(color: const Color(0xffe9efff), borderRadius: BorderRadius.circular(22)), child: Icon(icon, color: _blue, size: 30)),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _ink, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 7),
            Text(message, style: const TextStyle(color: Color(0xff6e7a91), height: 1.45), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ]),
        ),
      );
}
