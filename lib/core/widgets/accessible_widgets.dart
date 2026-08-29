import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../models/enums.dart';

/// Central helper for accessibility semantics, spoken announcements,
/// and Color Vision Deficiency (CVD) geometric symbol markers.
abstract final class AccessibleWidgets {
  /// Spoken voice announcement for TalkBack / VoiceOver screen readers.
  static void announce(String message, [BuildContext? context]) {
    if (message.trim().isEmpty) return;
    try {
      if (context != null) {
        final view = View.of(context);
        SemanticsService.sendAnnouncement(view, message, TextDirection.ltr);
      } else {
        final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
        if (view != null) {
          SemanticsService.sendAnnouncement(view, message, TextDirection.ltr);
        }
      }
    } catch (_) {
      // Graceful fallback if semantics binding not available
    }
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
