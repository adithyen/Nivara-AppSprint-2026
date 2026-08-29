import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme.dart';
import '../../core/widgets/accessible_widgets.dart';
import '../../core/widgets/bouncy_tap.dart';
import 'accessibility_controller.dart';
import 'language_controller.dart';

/// Dedicated 2026-Level Accessibility Configuration Hub.
class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a11y = ref.watch(accessibilityControllerProvider);
    final a11yCtrl = ref.read(accessibilityControllerProvider.notifier);
    final currentLang = ref.watch(languageControllerProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final cardBg = isDark ? const Color(0xFF10161E) : Colors.white;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);

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
              border: Border.all(color: borderColor),
              boxShadow: [
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
                            if (a11y.hapticsEnabled) HapticFeedback.selectionClick();
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
                const SizedBox(height: 14),

                // Live Preview Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0C131D) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Typography Scaling Preview',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Nivara empowers citizens and municipal workers with verified physical evidence.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 28),

                // High Contrast Switch
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: a11y.highContrast,
                  onChanged: (v) {
                    if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                    a11yCtrl.setHighContrast(v);
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_high_contrast', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    'Enforces solid opaque backgrounds, 2px borders, and 7:1 AAA contrast for low-vision clarity.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
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
                    'Adds geometric symbol cues (▲ Critical, ◆ High, ■ Medium, ● Low) alongside color badges.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
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
              border: Border.all(color: borderColor),
              boxShadow: [
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
                    'Disables spring bounce transforms, continuous radar sweeps, and heavy animations to reduce motion sensitivity.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
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
              border: Border.all(color: borderColor),
              boxShadow: [
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
                    if (v) HapticFeedback.heavyImpact();
                  },
                  title: Text(
                    NivaraStrings.tr('a11y_haptics', currentLang),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    'Provides tactile physical pulses on sensor impact detections, PIN handshakes, and button presses.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),
                const Divider(height: 20),

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
                    'Announces live background road detections and status updates when Android TalkBack or iOS VoiceOver is active.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Live announcement test trigger
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      AccessibleWidgets.announce('Nivara civic accessibility speech engine is active.');
                      if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Spoken alert dispatched to TalkBack / VoiceOver screen reader.'),
                          ),
                        );
                    },
                    icon: const Icon(Icons.record_voice_over_rounded, size: 18),
                    label: const Text('Test Screen Reader Spoken Alert'),
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
