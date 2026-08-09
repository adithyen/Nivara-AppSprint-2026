import 'package:flutter/material.dart';

import '../../models/enums.dart';
import 'lf_form_screen.dart';

/// Report a lost item — a thin wrapper over the shared [LFFormScreen] pinned to
/// [LFItemType.lost].
class ReportLostScreen extends StatelessWidget {
  const ReportLostScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const LFFormScreen(itemType: LFItemType.lost);
}
