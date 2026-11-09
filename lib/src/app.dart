import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'client_home_screen.dart';
import 'client_list_screen.dart';
import 'sign_in_screen.dart';

class GetFitApp extends StatelessWidget {
  const GetFitApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Get Fit',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff6fae43),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const AuthGate(),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              Supabase.instance.client.auth.currentSession == null) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (Supabase.instance.client.auth.currentSession == null) {
            return const SignInScreen();
          }
          return const AccountScreen();
        },
      );
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<Map<String, dynamic>?> _profile;
  final _nameController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  Future<Map<String, dynamic>?> _loadProfile() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    return Supabase.instance.client
        .from('profiles')
        .select('id, role, full_name')
        .eq('id', userId)
        .maybeSingle();
  }

  Future<void> _createTrainerProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name.length > 120) {
      setState(() => _error = 'Enter your name (up to 120 characters).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('profiles').insert({
        'id': userId,
        'role': 'trainer',
        'full_name': name,
      });
      if (mounted) setState(() => _profile = _loadProfile());
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create your account. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Your account could not be loaded.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() => _profile = _loadProfile()),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    child: const Text('Sign out'),
                  ),
                ]),
              ),
            );
          }
          final profile = snapshot.data;
          if (profile == null) return _trainerSetup();
          if (profile['role'] == 'trainer') {
            return ClientListScreen(trainerName: profile['full_name'] as String);
          }
          return const ClientHomeScreen();
        },
      );

  Widget _trainerSetup() => Scaffold(
        appBar: AppBar(
          title: const Text('Set up your coach account'),
          actions: [IconButton(onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout), tooltip: 'Sign out')],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving ? null : _createTrainerProfile,
                  child: _saving ? const CircularProgressIndicator() : const Text('Create coach account'),
                ),
              ]),
            ),
          ),
        ),
      );
}