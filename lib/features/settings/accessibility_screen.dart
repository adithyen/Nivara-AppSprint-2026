import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import 'accessibility_controller.dart';
import 'language_controller.dart';

/// Dedicated Accessibility Configuration Hub.
/// Provides global controls for vision, colour correction, animation removal,
/// haptic feedback, tap debounce, and spoken alerts across the entire application.
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
          // ── SECTION 1: VISION & DISPLAY ──────────────────────────────────
          _SectionHeader(
            icon: Icons.visibility_rounded,
            color: const Color(0xFF00B0FF),
            title: NivaraStrings.tr('a11y_vision_title', currentLang),
            subtitle: NivaraStrings.tr('a11y_vision_sub', currentLang),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: borderColor,
                width: a11y.highContrast ? 2.5 : 1.0,
              ),
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
                // Text scaling
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      NivaraStrings.tr('a11y_text_size', currentLang),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${(a11y.textScaleFactor * 100).toInt()}%',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final scale in [1.0, 1.15, 1.30, 1.50]) ...[
                      Expanded(
                        child: BouncyTap(
                          onTap: () {
                            if (a11y.hapticsEnabled) HapticFeedback.selectionClick();
                            a11yCtrl.setTextScaleFactor(scale);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: a11y.textScaleFactor == scale
                                  ? primary.withValues(alpha: isDark ? 0.22 : 0.15)
                                  : (isDark
                                      ? const Color(0xFF141C26)
                                      : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: a11y.textScaleFactor == scale
                                    ? primary
                                    : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                                width: a11y.textScaleFactor == scale ? 2.0 : 1.0,
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
                                fontSize: 11.5,
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

                // High Contrast Colours Switch
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: a11y.highContrast,
                  onChanged: (v) {
                    if (a11y.hapticsEnabled) HapticFeedback.selectionClick();
                    a11yCtrl.setHighContrast(v);
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_high_contrast', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      NivaraStrings.tr('a11y_high_contrast_sub', currentLang),
                      style: TextStyle(
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 28),

                // Colour Correction
                Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 20, color: primary),
                    const SizedBox(width: 8),
                    Text(
                      NivaraStrings.tr('a11y_color_correction', currentLang),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  NivaraStrings.tr('a11y_color_correction_sub', currentLang),
                  style: TextStyle(
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Spectrum color bar preview
                _ColorSpectrumPreview(isDark: isDark),
                const SizedBox(height: 12),

                // Mode radio options
                for (final mode in ColorCorrectionMode.values)
                  _CorrectionRadioOption(
                    mode: mode,
                    selected: a11y.colorCorrectionMode == mode,
                    currentLang: currentLang,
                    isDark: isDark,
                    primary: primary,
                    onTap: () {
                      if (a11y.hapticsEnabled) HapticFeedback.selectionClick();
                      a11yCtrl.setColorCorrectionMode(mode);
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── SECTION 2: MOTION & ANIMATIONS ──────────────────────────────
          _SectionHeader(
            icon: Icons.motion_photos_off_rounded,
            color: const Color(0xFFFFB300),
            title: NivaraStrings.tr('a11y_motion_title', currentLang),
            subtitle: NivaraStrings.tr('a11y_motion_sub', currentLang),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: borderColor,
                width: a11y.highContrast ? 2.5 : 1.0,
              ),
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
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: a11y.removeAnimations,
              onChanged: (v) {
                if (a11y.hapticsEnabled) HapticFeedback.selectionClick();
                a11yCtrl.setRemoveAnimations(v);
              },
              title: Text(
                NivaraStrings.tr('a11y_remove_animations', currentLang),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  NivaraStrings.tr('a11y_remove_animations_sub', currentLang),
                  style: TextStyle(
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── SECTION 3: INTERACTION & TOUCH ──────────────────────────────
          _SectionHeader(
            icon: Icons.touch_app_rounded,
            color: const Color(0xFF00E676),
            title: NivaraStrings.tr('a11y_interaction_title', currentLang),
            subtitle: NivaraStrings.tr('a11y_interaction_sub', currentLang),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: borderColor,
                width: a11y.highContrast ? 2.5 : 1.0,
              ),
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
                // Single Haptic Feedback Toggle
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: a11y.hapticsEnabled,
                  onChanged: (v) {
                    a11yCtrl.setHapticsEnabled(v);
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_haptics', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      NivaraStrings.tr('a11y_haptics_sub', currentLang),
                      style: TextStyle(
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 28),

                // Ignore Repeated Taps Switch
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: a11y.ignoreRepeatedTaps,
                  onChanged: (v) {
                    if (a11y.hapticsEnabled) HapticFeedback.selectionClick();
                    a11yCtrl.setIgnoreRepeatedTaps(v);
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_ignore_repeated', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      NivaraStrings.tr('a11y_ignore_repeated_sub', currentLang),
                      style: TextStyle(
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),

                // Duration Stepper (only shown when Ignore Repeated Taps is ON)
                if (a11y.ignoreRepeatedTaps) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141C26) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              NivaraStrings.tr('a11y_tap_duration', currentLang),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: isDark ? 0.2 : 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${a11y.ignoreRepeatDuration.toStringAsFixed(2)}s',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            // Decrement Button
                            Expanded(
                              child: BouncyTap(
                                onTap: a11y.ignoreRepeatDuration > 0.10
                                    ? () {
                                        if (a11y.hapticsEnabled) {
                                          HapticFeedback.selectionClick();
                                        }
                                        final next = a11y.ignoreRepeatDuration - 0.05;
                                        a11yCtrl.setIgnoreRepeatDuration(next);
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: a11y.ignoreRepeatDuration > 0.10
                                        ? (isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFE2E8F0))
                                        : (isDark
                                            ? Colors.white.withValues(alpha: 0.04)
                                            : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.remove_rounded,
                                    size: 20,
                                    color: a11y.ignoreRepeatDuration > 0.10
                                        ? (isDark ? Colors.white : Colors.black87)
                                        : (isDark ? Colors.white24 : Colors.black26),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Increment Button
                            Expanded(
                              child: BouncyTap(
                                onTap: a11y.ignoreRepeatDuration < 4.00
                                    ? () {
                                        if (a11y.hapticsEnabled) {
                                          HapticFeedback.selectionClick();
                                        }
                                        final next = a11y.ignoreRepeatDuration + 0.05;
                                        a11yCtrl.setIgnoreRepeatDuration(next);
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: a11y.ignoreRepeatDuration < 4.00
                                        ? (isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFE2E8F0))
                                        : (isDark
                                            ? Colors.white.withValues(alpha: 0.04)
                                            : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 20,
                                    color: a11y.ignoreRepeatDuration < 4.00
                                        ? (isDark ? Colors.white : Colors.black87)
                                        : (isDark ? Colors.white24 : Colors.black26),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Range: 0.10s – 4.00s (0.05s increments)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── SECTION 4: VOICE ALERTS ─────────────────────────────────────
          _SectionHeader(
            icon: Icons.record_voice_over_rounded,
            color: const Color(0xFFFF5252),
            title: NivaraStrings.tr('a11y_voice_title', currentLang),
            subtitle: NivaraStrings.tr('a11y_voice_sub', currentLang),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: borderColor,
                width: a11y.highContrast ? 2.5 : 1.0,
              ),
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
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: a11y.voiceAlertsEnabled,
              onChanged: (v) {
                if (a11y.hapticsEnabled) HapticFeedback.selectionClick();
                a11yCtrl.setVoiceAlertsEnabled(v);
              },
              title: Text(
                NivaraStrings.tr('a11y_voice_alerts', currentLang),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  NivaraStrings.tr('a11y_voice_alerts_sub', currentLang),
                  style: TextStyle(
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── SUBWIDGETS ──────────────────────────────────────────────────────────────

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.18 : 0.12),
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorSpectrumPreview extends StatelessWidget {
  const _ColorSpectrumPreview({required this.isDark});

  final bool isDark;

  static const List<Color> _spectrum = [
    Color(0xFFE53935), // Red
    Color(0xFFFB8C00), // Orange
    Color(0xFFFDD835), // Yellow
    Color(0xFF43A047), // Green
    Color(0xFF00ACC1), // Cyan
    Color(0xFF1E88E5), // Blue
    Color(0xFF8E24AA), // Purple
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final color in _spectrum)
            Expanded(
              child: Container(color: color),
            ),
        ],
      ),
    );
  }
}

class _CorrectionRadioOption extends StatelessWidget {
  const _CorrectionRadioOption({
    required this.mode,
    required this.selected,
    required this.currentLang,
    required this.isDark,
    required this.primary,
    required this.onTap,
  });

  final ColorCorrectionMode mode;
  final bool selected;
  final AppLanguage currentLang;
  final bool isDark;
  final Color primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleKey = switch (mode) {
      ColorCorrectionMode.none => 'a11y_color_off',
      ColorCorrectionMode.deuteranomaly => 'a11y_color_deuteranomaly',
      ColorCorrectionMode.protanomaly => 'a11y_color_protanomaly',
      ColorCorrectionMode.tritanomaly => 'a11y_color_tritanomaly',
      ColorCorrectionMode.greyscale => 'a11y_color_greyscale',
    };

    return BouncyTap(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: isDark ? 0.16 : 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? primary
                : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected
                  ? primary
                  : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                NivaraStrings.tr(titleKey, currentLang),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? (isDark ? Colors.white : Colors.black87)
                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
