import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/services/debug_logger.dart';
import 'features/settings/settings_controller.dart';

/// App entry point: load env → init Supabase → run inside a Riverpod scope.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open the on-device file logger first so we capture startup + map failures.
  await DebugLogger.instance.init();
  DebugLogger.instance.log('BOOT', 'main() start');

  await dotenv.load(fileName: '.env');
  DebugLogger.instance.log(
    'BOOT',
    '.env loaded (OLA key present: ${(dotenv.env['OLA_MAPS_API_KEY'] ?? '').isNotEmpty})',
  );

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (supabaseUrl == null || supabaseAnonKey == null) {
    throw StateError(
      'Missing SUPABASE_URL / SUPABASE_ANON_KEY in .env — see .env.example.',
    );
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  DebugLogger.instance.log('BOOT', 'Supabase initialized → runApp');

  // Preload settings so theme mode + accent apply on the very first frame.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const NivaraApp(),
    ),
  );
}
