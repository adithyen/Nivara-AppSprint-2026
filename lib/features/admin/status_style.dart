import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/accessible_widgets.dart';
import '../../models/enums.dart';
import '../settings/accessibility_controller.dart';

/// Shared status/severity styling for the municipal side, so the queue, the
/// stats strip, and the report detail all speak the same visual language.
/// Colours mirror the map pin convention in CivicMap.
Color statusColor(ReportStatus s) => switch (s) {
  ReportStatus.submitted => NivaraColors.accent,
  ReportStatus.acknowledged => NivaraColors.primary,
  ReportStatus.inProgress => NivaraColors.primary,
  ReportStatus.resolved => NivaraColors.success,
  ReportStatus.closed => Colors.blueGrey,
  ReportStatus.duplicate => Colors.blueGrey,
};

IconData statusIcon(ReportStatus s) => switch (s) {
  ReportStatus.submitted => Icons.fiber_new,
  ReportStatus.acknowledged => Icons.visibility,
  ReportStatus.inProgress => Icons.engineering,
  ReportStatus.resolved => Icons.check_circle,
  ReportStatus.closed => Icons.lock,
  ReportStatus.duplicate => Icons.copy_all,
};

Color severityColor(Severity s) => switch (s) {
  Severity.low => NivaraColors.success,
  Severity.medium => NivaraColors.accent,
  Severity.high => NivaraColors.danger,
  Severity.emergency => NivaraColors.danger,
};

/// A compact pill showing a report's [ReportStatus] with its icon + colour and accessibility tags.
class StatusChip extends ConsumerWidget {
  const StatusChip(this.status, {super.key, this.dense = false});

  final ReportStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a11y = ref.watch(accessibilityControllerProvider);
    final c = statusColor(status);
    final symbol = a11y.colorCorrectionMode != ColorCorrectionMode.none ? '${AccessibleWidgets.statusSymbol(status)} ' : '';

    return Semantics(
      label: 'Status: ${status.label}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: c.withValues(alpha: a11y.highContrast ? 0.28 : 0.14),
          borderRadius: BorderRadius.circular(20),
          border: a11y.highContrast ? Border.all(color: c, width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon(status), size: dense ? 13 : 15, color: c),
            const SizedBox(width: 5),
            Text(
              '$symbol${status.label}',
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.w700,
                fontSize: dense ? 11 : 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
