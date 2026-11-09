import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'client_workout_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  late Stream<List<Map<String, dynamic>>> _clientRecord;

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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('My profile'),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
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
              return _ClientMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Your profile could not be loaded',
                message: 'Check your connection, then try again.',
                action: TextButton.icon(
                  onPressed: () => setState(() => _clientRecord = _watchRecord()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              );
            }
            final records = snapshot.data ?? [];
            final client = records.isEmpty ? null : records.first;
            if (client == null) {
              return const _ClientMessage(
                icon: Icons.person_search_outlined,
                title: 'Client profile unavailable',
                message: 'Your trainer may need to resend your invitation. Contact them for help.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => setState(() => _clientRecord = _watchRecord()),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Welcome, ${client['full_name']}', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Training goal', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(client['goal'] as String),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Body weight', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _WeightRow(label: 'Starting', value: client['starting_weight_kg']),
                        _WeightRow(label: 'Current', value: client['current_weight_kg']),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(client['status'] == 'active' ? Icons.check_circle_outline : Icons.pause_circle_outline),
                    title: Text(client['status'] == 'active' ? 'Training active' : 'Training paused'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: client['status'] == 'active'
                        ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => const ClientWorkoutScreen(),
                            ))
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Open today’s workout'),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class _WeightRow extends StatelessWidget {
  const _WeightRow({required this.label, required this.value});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label),
          Text(value == null ? 'Not recorded' : '$value kg'),
        ]),
      );
}

class _ClientMessage extends StatelessWidget {
  const _ClientMessage({required this.icon, required this.title, required this.message, this.action});

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