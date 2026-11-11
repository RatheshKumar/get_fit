import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    runApp(const ConfigurationRequiredApp());
    return;
  }

  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
    runApp(const GetFitApp());
  } catch (error) {
    runApp(ConfigurationRequiredApp(error: error.toString()));
  }
}

class ConfigurationRequiredApp extends StatelessWidget {
  const ConfigurationRequiredApp({super.key, this.error});

  final String? error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Get Fit',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1769e0)),
          scaffoldBackgroundColor: const Color(0xfff5f8ff),
        ),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connect your Supabase project',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    const Text(
                      'Run the app with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY '
                      'configured. Find both in your Supabase project settings.',
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}