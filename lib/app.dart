import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'features/settings/settings_controller.dart';
import 'router.dart';

/// Root widget: wires the router + theme into [MaterialApp.router]. Theme mode
/// and accent colour follow the user's [AppSettings].
class NivaraApp extends ConsumerWidget {
  const NivaraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final seed = settings.accent.color;
    return MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: NivaraTheme.light(seed),
      darkTheme: NivaraTheme.dark(seed),
      themeMode: settings.themeMode,
      routerConfig: router,
    );
  }
}
