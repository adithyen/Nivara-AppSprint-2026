import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/offline_queue_service.dart';
import 'core/theme.dart';
import 'features/settings/accessibility_controller.dart';
import 'features/settings/settings_controller.dart';
import 'router.dart';

/// Root widget: wires the router, theme, and accessibility pipeline into [MaterialApp.router].
/// Theme mode and accent colour follow the user's [AppSettings], while font scaling,
/// motion reduction, and high contrast follow [AccessibilityState].
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
    final a11y = ref.watch(accessibilityControllerProvider);
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
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final currentMq = MediaQuery.of(context);
        return MediaQuery(
          data: currentMq.copyWith(
            textScaler: TextScaler.linear(a11y.textScaleFactor),
            disableAnimations: a11y.reduceMotion || currentMq.disableAnimations,
            highContrast: a11y.highContrast || currentMq.highContrast,
          ),
          child: child,
        );
      },
    );
  }
}
