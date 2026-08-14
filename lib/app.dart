import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/offline_queue_service.dart';
import 'core/theme.dart';
import 'features/settings/settings_controller.dart';
import 'router.dart';

/// Root widget: wires the router + theme into [MaterialApp.router]. Theme mode
/// and accent colour follow the user's [AppSettings].
///
/// Also watches [connectivityProvider] to auto-drain the offline queue when
/// the device comes back online.
class NivaraApp extends ConsumerStatefulWidget {
  const NivaraApp({super.key});

  @override
  ConsumerState<NivaraApp> createState() => _NivaraAppState();
}

class _NivaraAppState extends ConsumerState<NivaraApp> {
  bool _prevOnline = true;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final seed = settings.accent.color;

    // Watch connectivity — drain the queue when we come back online.
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      final nowOnline = next.value ?? true;
      if (nowOnline && !_prevOnline) {
        // Came back online — drain the queue silently in the background.
        OfflineQueueService.drainAll();
      }
      _prevOnline = nowOnline;
    });

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

