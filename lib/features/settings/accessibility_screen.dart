import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme.dart';
import '../../core/widgets/accessible_widgets.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import 'accessibility_controller.dart';
import 'language_controller.dart';

/// Dedicated 2026-Level Accessibility Configuration Hub with live interactive previews.
class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a11y = ref.watch(accessibilityControllerProvider);
    final a11yCtrl = ref.read(accessibilityControllerProvider.notifier);
    final currentLang = ref.watch(languageControllerProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final cardBg = a11y.highContrast
        ? (isDark ? Colors.black : Colors.white)
        : (isDark ? const Color(0xFF10161E) : Colors.white);
    final borderColor = a11y.highContrast
        ? primary
        : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          NivaraStrings.tr('settings_accessibility', currentLang),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          // ── SECTION 1: VISION & TYPOGRAPHY ──────────────────────────────
          _SectionHeader(
            icon: Icons.text_fields_rounded,
            color: const Color(0xFF00B0FF),
            title: 'Vision & Typography',
            subtitle: 'Dynamic text scaling, contrast, and color blindness assistance',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: a11y.highContrast ? 2.5 : 1.0),
              boxShadow: a11y.highContrast
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      NivaraStrings.tr('a11y_text_scale', currentLang),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${(a11y.textScaleFactor * 100).toInt()}%',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final scale in [1.0, 1.15, 1.30, 1.50]) ...[
                      Expanded(
                        child: BouncyTap(
                          onTap: () {
                            if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                            a11yCtrl.setTextScaleFactor(scale);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: a11y.textScaleFactor == scale
                                  ? primary.withValues(alpha: isDark ? 0.22 : 0.15)
                                  : (isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: a11y.textScaleFactor == scale
                                    ? primary
                                    : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                                width: a11y.textScaleFactor == scale ? 1.5 : 1.0,
                              ),
                            ),
                            child: Text(
                              switch (scale) {
                                1.0 => '1.0×\nNormal',
                                1.15 => '1.15×\nLarge',
                                1.30 => '1.3×\nX-Large',
                                _ => '1.5×\nMax',
                              },
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: a11y.textScaleFactor == scale
                                    ? primary
                                    : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                fontWeight: a11y.textScaleFactor == scale
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: 11,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (scale != 1.50) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const Divider(height: 28),

                // High Contrast Switch
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: a11y.highContrast,
                  onChanged: (v) {
                    if (a11y.hapticsEnabled) {
                      HapticFeedback.vibrate();
                      HapticFeedback.heavyImpact();
                    }
                    a11yCtrl.setHighContrast(v);
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_high_contrast', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    'Enforces solid opaque backgrounds, 2.5px solid neon borders, and 7:1 AAA contrast for maximum readability.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),

                // High Contrast Live Visual Box
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: a11y.highContrast
                        ? (isDark ? Colors.black : Colors.white)
                        : (isDark ? const Color(0xFF0C131D) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: a11y.highContrast
                          ? primary
                          : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                      width: a11y.highContrast ? 2.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        a11y.highContrast ? Icons.contrast_rounded : Icons.palette_outlined,
                        color: primary,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a11y.highContrast
                                  ? 'High Contrast 7:1 AAA Mode: ACTIVE'
                                  : 'High Contrast Mode: Standard',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: a11y.highContrast ? primary : (isDark ? Colors.white : Colors.black),
                              ),
                            ),
                            Text(
                              a11y.highContrast
                                  ? 'Cards & buttons use 100% solid surfaces and high-visibility borders.'
                                  : 'Standard cyber-civic frosted glass and subtle alpha borders.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 20),

                // Color Blindness Assistance Switch
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: a11y.colorBlindAssistance,
                  onChanged: (v) {
                    if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                    a11yCtrl.setColorBlindAssistance(v);
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_color_blind', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    'Adds geometric shape cues alongside color badges to distinguish statuses without color perception.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),

                // CVD Live Shape Samples
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SeveritySampleChip(
                      severity: Severity.emergency,
                      label: 'Emergency',
                      color: NivaraColors.danger,
                      showShape: a11y.colorBlindAssistance,
                      isDark: isDark,
                    ),
                    _SeveritySampleChip(
                      severity: Severity.high,
                      label: 'High',
                      color: NivaraColors.warning,
                      showShape: a11y.colorBlindAssistance,
                      isDark: isDark,
                    ),
                    _SeveritySampleChip(
                      severity: Severity.medium,
                      label: 'Medium',
                      color: NivaraColors.accent,
                      showShape: a11y.colorBlindAssistance,
                      isDark: isDark,
                    ),
                    _SeveritySampleChip(
                      severity: Severity.low,
                      label: 'Low',
                      color: NivaraColors.primary,
                      showShape: a11y.colorBlindAssistance,
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── SECTION 2: MOTION & ANIMATIONS ──────────────────────────────
          _SectionHeader(
            icon: Icons.motion_photos_off_rounded,
            color: const Color(0xFFFFB300),
            title: 'Motion & Animations',
            subtitle: 'Vestibular comfort and dynamic transform controls',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: a11y.highContrast ? 2.5 : 1.0),
              boxShadow: a11y.highContrast
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: a11y.reduceMotion,
                  onChanged: (v) {
                    if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                    a11yCtrl.setReduceMotion(v);
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_reduce_motion', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    'Disables spring bounces, continuous radar pulses, and moving transforms for vestibular comfort.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Interactive Motion Tester Button
                BouncyTap(
                  onTap: () {
                    if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 1),
                          content: Text(
                            a11y.reduceMotion
                                ? 'Reduce Motion is ON: Tap uses instant opacity snap.'
                                : 'Reduce Motion is OFF: Tap uses physical spring bounce.',
                          ),
                        ),
                      );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          a11y.reduceMotion ? Icons.touch_app_outlined : Icons.animation_rounded,
                          size: 18,
                          color: primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          a11y.reduceMotion
                              ? 'Tap to Test Instant Touch Response'
                              : 'Tap to Test Spring Bounce Dynamics',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── SECTION 3: TACTILE HAPTICS & SCREEN READERS ─────────────────
          _SectionHeader(
            icon: Icons.vibration_rounded,
            color: const Color(0xFF00E676),
            title: 'Tactile & Assistive Feedback',
            subtitle: 'Physical vibration haptics and TalkBack voice feedback',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: a11y.highContrast ? 2.5 : 1.0),
              boxShadow: a11y.highContrast
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: a11y.hapticsEnabled,
                  onChanged: (v) {
                    a11yCtrl.setHapticsEnabled(v);
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_haptics', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    'Emits physical vibrator motor pulses on pothole impacts, navigation tabs, and button taps.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Live Haptic Pulse Test Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.vibrate();
                      HapticFeedback.heavyImpact();
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            duration: Duration(seconds: 1),
                            content: Text('Tactile physical haptic pulse triggered!'),
                          ),
                        );
                    },
                    icon: const Icon(Icons.vibration_rounded, size: 18),
                    label: const Text('Test Physical Vibration Pulse'),
                  ),
                ),

                const Divider(height: 24),

                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: a11y.screenReaderAnnouncements,
                  onChanged: (v) {
                    if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                    a11yCtrl.setScreenReaderAnnouncements(v);
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_voice_alerts', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    'Announces background road events and status updates to Android TalkBack & iOS VoiceOver screen readers.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Live Screen Reader Announcement Test Trigger
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      AccessibleWidgets.announce('Nivara civic accessibility speech channel is active.');
                      if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Spoken alert dispatched to Android TalkBack / iOS VoiceOver.',
                            ),
                          ),
                        );
                    },
                    icon: const Icon(Icons.record_voice_over_rounded, size: 18),
                    label: const Text('Test Screen Reader Announcement'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeveritySampleChip extends StatelessWidget {
  const _SeveritySampleChip({
    required this.severity,
    required this.label,
    required this.color,
    required this.showShape,
    required this.isDark,
  });

  final Severity severity;
  final String label;
  final Color color;
  final bool showShape;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final symbol = AccessibleWidgets.severitySymbol(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showShape) ...[
            Text(
              symbol,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
