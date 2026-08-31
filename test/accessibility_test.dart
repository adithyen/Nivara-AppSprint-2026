import 'package:flutter_test/flutter_test.dart';
import 'package:nivara/core/localization/app_localizations.dart';
import 'package:nivara/core/widgets/accessible_widgets.dart';
import 'package:nivara/features/settings/accessibility_controller.dart';
import 'package:nivara/features/settings/language_controller.dart';
import 'package:nivara/models/enums.dart';

void main() {
  group('AccessibilityState', () {
    test('default state has expected initial values', () {
      const state = AccessibilityState();
      expect(state.textScaleFactor, 1.0);
      expect(state.highContrast, isFalse);
      expect(state.removeAnimations, isFalse);
      expect(state.colorCorrectionMode, ColorCorrectionMode.none);
      expect(state.hapticsEnabled, isFalse);
      expect(state.ignoreRepeatedTaps, isFalse);
      expect(state.ignoreRepeatDuration, 0.30);
      expect(state.voiceAlertsEnabled, isFalse);
    });

    test('copyWith updates state immutably', () {
      const state = AccessibilityState();
      final updated = state.copyWith(
        textScaleFactor: 1.3,
        highContrast: true,
        removeAnimations: true,
        colorCorrectionMode: ColorCorrectionMode.deuteranomaly,
        hapticsEnabled: true,
        ignoreRepeatedTaps: true,
        ignoreRepeatDuration: 0.75,
        voiceAlertsEnabled: true,
      );

      expect(updated.textScaleFactor, 1.3);
      expect(updated.highContrast, isTrue);
      expect(updated.removeAnimations, isTrue);
      expect(updated.colorCorrectionMode, ColorCorrectionMode.deuteranomaly);
      expect(updated.hapticsEnabled, isTrue);
      expect(updated.ignoreRepeatedTaps, isTrue);
      expect(updated.ignoreRepeatDuration, 0.75);
      expect(updated.voiceAlertsEnabled, isTrue);
    });
  });

  group('AccessibleWidgets CVD Geometric Markers', () {
    test('severity symbols return distinctive non-color geometric shapes', () {
      expect(AccessibleWidgets.severitySymbol(Severity.emergency), '▲');
      expect(AccessibleWidgets.severitySymbol(Severity.high), '◆');
      expect(AccessibleWidgets.severitySymbol(Severity.medium), '■');
      expect(AccessibleWidgets.severitySymbol(Severity.low), '●');
    });

    test('status symbols return distinctive non-color geometric shapes', () {
      expect(AccessibleWidgets.statusSymbol(ReportStatus.submitted), '○');
      expect(AccessibleWidgets.statusSymbol(ReportStatus.acknowledged), '◔');
      expect(AccessibleWidgets.statusSymbol(ReportStatus.inProgress), '◑');
      expect(AccessibleWidgets.statusSymbol(ReportStatus.resolved), '✓');
      expect(AccessibleWidgets.statusSymbol(ReportStatus.closed), '●');
      expect(AccessibleWidgets.statusSymbol(ReportStatus.duplicate), '✕');
    });
  });

  group('NivaraStrings & AppLanguage Localizations', () {
    test('localizes core strings across English, Hindi, and Malayalam', () {
      expect(NivaraStrings.tr('app_name', AppLanguage.en), 'Nivara');
      expect(NivaraStrings.tr('app_name', AppLanguage.hi), 'निवारा');
      expect(NivaraStrings.tr('app_name', AppLanguage.ml), 'നിവാര');

      expect(NivaraStrings.tr('role_citizen', AppLanguage.hi), 'नागरिक');
      expect(NivaraStrings.tr('role_citizen', AppLanguage.ml), 'പൗരൻ');
      expect(NivaraStrings.tr('role_admin', AppLanguage.hi), 'नगर निगम अधिकारी');
      expect(NivaraStrings.tr('role_admin', AppLanguage.ml), 'നഗരസഭാ ഉദ്യോഗസ്ഥൻ');

      expect(NivaraStrings.tr('settings_accessibility', AppLanguage.en), 'Accessibility');
      expect(NivaraStrings.tr('settings_accessibility', AppLanguage.hi), 'सुलभता');
      expect(NivaraStrings.tr('settings_accessibility', AppLanguage.ml), 'പ്രവേശനക്ഷമത');
      expect(NivaraStrings.tr('a11y_high_contrast', AppLanguage.en), 'High contrast colours');
      expect(NivaraStrings.tr('a11y_remove_animations', AppLanguage.en), 'Remove animations');
      expect(NivaraStrings.tr('a11y_ignore_repeated', AppLanguage.en), 'Ignore repeated taps');
    });

    test('Indian official languages list contains all 22 Eighth Schedule languages', () {
      expect(kAllIndianOfficialLanguages.length, greaterThanOrEqualTo(22));
      expect(kAllIndianOfficialLanguages.any((l) => l.code == 'hi' && l.isFullyLocalized), isTrue);
      expect(kAllIndianOfficialLanguages.any((l) => l.code == 'ml' && l.isFullyLocalized), isTrue);
      expect(kAllIndianOfficialLanguages.any((l) => l.code == 'ta'), isTrue);
      expect(kAllIndianOfficialLanguages.any((l) => l.code == 'kn'), isTrue);
    });
  });
}
