import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/offline_queue_service.dart';
import 'core/theme.dart';
import 'features/settings/accessibility_controller.dart';
import 'features/settings/settings_controller.dart';
import 'models/enums.dart';
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

    Widget app = MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: NivaraTheme.light(seed, a11y.highContrast),
      darkTheme: NivaraTheme.dark(seed, a11y.highContrast),
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final currentMq = MediaQuery.of(context);
        return MediaQuery(
          data: currentMq.copyWith(
            textScaler: TextScaler.linear(a11y.textScaleFactor),
            disableAnimations: a11y.removeAnimations || currentMq.disableAnimations,
            highContrast: a11y.highContrast || currentMq.highContrast,
          ),
          child: NivaraA11yData(
            ignoreRepeatedTaps: a11y.ignoreRepeatedTaps,
            ignoreRepeatDuration: Duration(
              milliseconds: (a11y.ignoreRepeatDuration * 1000).round(),
            ),
            hapticsEnabled: a11y.hapticsEnabled,
            child: child,
          ),
        );
      },
    );

    // Apply colour correction filter at the root level (affects entire app)
    final colorFilter = _colorFilterForMode(a11y.colorCorrectionMode);
    if (colorFilter != null) {
      app = ColorFiltered(colorFilter: colorFilter, child: app);
    }

    return app;
  }

  /// Returns a [ColorFilter] matrix for the given colour correction mode,
  /// or null if no correction is needed.
  static ColorFilter? _colorFilterForMode(ColorCorrectionMode mode) {
    return switch (mode) {
      ColorCorrectionMode.none => null,
      ColorCorrectionMode.deuteranomaly => const ColorFilter.matrix(<double>[
        0.80, 0.20, 0.0, 0, 0,
        0.26, 0.74, 0.0, 0, 0,
        0.0,  0.14, 0.86, 0, 0,
        0,    0,    0,    1, 0,
      ]),
      ColorCorrectionMode.protanomaly => const ColorFilter.matrix(<double>[
        0.82, 0.18, 0.0, 0, 0,
        0.33, 0.67, 0.0, 0, 0,
        0.0,  0.13, 0.87, 0, 0,
        0,    0,    0,    1, 0,
      ]),
      ColorCorrectionMode.tritanomaly => const ColorFilter.matrix(<double>[
        0.97, 0.03, 0.0,  0, 0,
        0.0,  0.73, 0.27, 0, 0,
        0.0,  0.18, 0.82, 0, 0,
        0,    0,    0,    1, 0,
      ]),
      ColorCorrectionMode.greyscale => const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0,      0,      0,      1, 0,
      ]),
    };
  }
}

/// InheritedWidget that provides tap-debounce and haptic configuration
/// to all descendant widgets (especially [BouncyTap]).
class NivaraA11yData extends InheritedWidget {
  const NivaraA11yData({
    super.key,
    required this.ignoreRepeatedTaps,
    required this.ignoreRepeatDuration,
    required this.hapticsEnabled,
    required super.child,
  });

  final bool ignoreRepeatedTaps;
  final Duration ignoreRepeatDuration;
  final bool hapticsEnabled;

  static NivaraA11yData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NivaraA11yData>();

  @override
  bool updateShouldNotify(NivaraA11yData oldWidget) =>
      ignoreRepeatedTaps != oldWidget.ignoreRepeatedTaps ||
      ignoreRepeatDuration != oldWidget.ignoreRepeatDuration ||
      hapticsEnabled != oldWidget.hapticsEnabled;
}
