import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identity = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _signUp = false;
  bool _working = false;
  bool _obscure = true;
  String? _error;

  String _authEmail(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('@')) return normalized;
    return '${_authIdentity(value)}@example.com';
  }

  String _authIdentity(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.startsWith('+') || RegExp(r'^[0-9(]').hasMatch(normalized)) {
      return normalized.replaceAll(RegExp(r'[^0-9]'), '');
    }
    return normalized;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      final email = _authEmail(_identity.text);
      if (_signUp) {
        await Supabase.instance.client.functions.invoke('create-trainer', body: {
          'login_id': _identity.text.trim(),
          'full_name': _name.text.trim(),
          'password': _password.text.trim(),
        });
      }
      await auth.signInWithPassword(email: email, password: _password.text.trim());
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } on FunctionException catch (error) {
      if (mounted) setState(() => _error = error.details?.toString() ?? 'Could not create your account.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not connect. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('already registered') || message.contains('already been registered')) {
      return 'That username or phone number is already registered. Try signing in.';
    }
    if (message.contains('invalid login credentials')) return 'Username or password is incorrect.';
    return error.message;
  }

  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    _name.dispose();
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
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Align(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(24)),
                        child: Icon(Icons.fitness_center, size: 38, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(_signUp ? 'Create your coach account' : 'Welcome to Get Fit', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(_signUp ? 'Sign up with your email, username, or phone and a password.' : 'Sign in with your email, username, or phone and password.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 28),
                    if (_signUp) ...[
                      TextFormField(controller: _name, textCapitalization: TextCapitalization.words, maxLength: 120, decoration: const InputDecoration(labelText: 'Your name'), validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter your name.' : null),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _identity,
                      keyboardType: TextInputType.text,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Email, username, or phone number', prefixIcon: Icon(Icons.person_outline)),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Enter your email, username, or phone number.';
                        if (text.contains('@') && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) return 'Enter a valid email address.';
                        if (!text.contains('@') && !RegExp(r'^[a-zA-Z0-9_.+() -]{3,40}$').hasMatch(text)) return 'Use 3–40 letters, numbers, or a phone number.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                      decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
                      validator: (value) {
                        final password = value ?? '';
                        if (password.length < 8) return 'Use at least 8 characters.';
                        if (password.length > 72) return 'Password must be 72 characters or fewer.';
                        return null;
                      },
                      onFieldSubmitted: (_) => _working ? null : _submit(),
                    ),
                    if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
                    const SizedBox(height: 20),
                    FilledButton(onPressed: _working ? null : _submit, child: _working ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_signUp ? 'Create account' : 'Sign in')),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _working ? null : () => setState(() { _signUp = !_signUp; _error = null; }), child: Text(_signUp ? 'Already have an account? Sign in' : 'New coach? Create an account')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
