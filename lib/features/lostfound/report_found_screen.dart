import 'package:flutter/material.dart';

import '../../models/enums.dart';
import 'lf_form_screen.dart';

/// Report a found item — a thin wrapper over the shared [LFFormScreen] pinned to
/// [LFItemType.found].
class ReportFoundScreen extends StatelessWidget {
  const ReportFoundScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const LFFormScreen(itemType: LFItemType.found);
}
