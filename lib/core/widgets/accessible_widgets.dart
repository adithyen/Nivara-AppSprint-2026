import 'package:flutter/widgets.dart';

import '../../models/enums.dart';
import '../services/voice_alert_service.dart';

/// Central helper for accessibility semantics, spoken announcements,
/// and Color Vision Deficiency (CVD) geometric symbol markers.
abstract final class AccessibleWidgets {
  /// Speak a voice alert through the device speaker using flutter_tts.
  /// This works independently of Android TalkBack / iOS VoiceOver.
  static Future<void> announce(String message, [BuildContext? context]) async {
    if (message.trim().isEmpty) return;
    await VoiceAlertService.speak(message);
  }

  /// Geometric symbol marker for severity to assist users with color blindness.
  static String severitySymbol(Severity severity) {
    return switch (severity) {
      Severity.emergency => '▲',
      Severity.high => '◆',
      Severity.medium => '■',
      Severity.low => '●',
    };
  }

  /// Geometric symbol marker for report status to assist users with color blindness.
  static String statusSymbol(ReportStatus status) {
    return switch (status) {
      ReportStatus.submitted => '○',
      ReportStatus.acknowledged => '◔',
      ReportStatus.inProgress => '◑',
      ReportStatus.resolved => '✓',
      ReportStatus.closed => '●',
      ReportStatus.duplicate => '✕',
    };
  }
}
