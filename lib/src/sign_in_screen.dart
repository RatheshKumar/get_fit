import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  Future<void> _sendLink() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _sent = false;
    });
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
        emailRedirectTo: const String.fromEnvironment('AUTH_REDIRECT_URL').isEmpty
            ? null
            : const String.fromEnvironment('AUTH_REDIRECT_URL'),
      );
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send the sign-in link. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.fitness_center, size: 44, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 20),
                  Text('Get Fit', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  const Text('Sign in or create your account with a secure email link.', textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _sending ? null : _sendLink(),
                    decoration: const InputDecoration(labelText: 'Email address'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  if (_sent) ...[
                    const SizedBox(height: 12),
                    const Text('Check your email for a secure sign-in link.'),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _sending ? null : _sendLink,
                    child: _sending ? const CircularProgressIndicator() : const Text('Email me a sign-in link'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}