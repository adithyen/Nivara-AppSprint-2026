import 'package:flutter_test/flutter_test.dart';
import 'package:nivara/core/widgets/accessible_widgets.dart';
import 'package:nivara/features/settings/accessibility_controller.dart';
import 'package:nivara/models/enums.dart';

void main() {
  group('AccessibilityState', () {
    test('default state has expected initial values', () {
      const state = AccessibilityState();
      expect(state.reduceMotion, isFalse);
      expect(state.textScaleFactor, 1.0);
      expect(state.highContrast, isFalse);
      expect(state.colorBlindAssistance, isFalse);
      expect(state.hapticsEnabled, isTrue);
      expect(state.screenReaderAnnouncements, isTrue);
    });

    test('copyWith updates state immutably', () {
      const state = AccessibilityState();
      final updated = state.copyWith(
        reduceMotion: true,
        textScaleFactor: 1.3,
        highContrast: true,
        colorBlindAssistance: true,
        hapticsEnabled: false,
        screenReaderAnnouncements: false,
      );

      expect(updated.reduceMotion, isTrue);
      expect(updated.textScaleFactor, 1.3);
      expect(updated.highContrast, isTrue);
      expect(updated.colorBlindAssistance, isTrue);
      expect(updated.hapticsEnabled, isFalse);
      expect(updated.screenReaderAnnouncements, isFalse);
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
}
