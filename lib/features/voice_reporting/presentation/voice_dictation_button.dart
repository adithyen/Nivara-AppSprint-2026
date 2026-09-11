import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../models/enums.dart';
import '../models/voice_reporting_models.dart';
import 'voice_reporting_sheet.dart';

/// Reusable tactile voice button that opens the Nivara Voice Assistant.
/// Implements Emil Kowalski scale-down spring bounce on tap.
class VoiceDictationButton extends StatefulWidget {
  final VoiceReportMode mode;
  final CommunityPostType? initialCommunityType;
  final String? tooltip;
  final Function(VoiceReportPayload)? onPayloadReceived;
  final bool isCompact;

  const VoiceDictationButton({
    super.key,
    required this.mode,
    this.initialCommunityType,
    this.tooltip,
    this.onPayloadReceived,
    this.isCompact = false,
  });

  @override
  State<VoiceDictationButton> createState() => _VoiceDictationButtonState();
}

class _VoiceDictationButtonState extends State<VoiceDictationButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _scaleController.forward();
    HapticFeedback.selectionClick();
  }

  void _onTapUp(TapUpDetails _) {
    _scaleController.reverse();
    showVoiceReportingSheet(
      context,
      initialMode: widget.mode,
      initialCommunityType: widget.initialCommunityType,
      onPayloadReady: widget.onPayloadReceived,
    );
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.isCompact ? 10 : 14,
            vertical: widget.isCompact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: NivaraColors.primary.withValues(alpha: 0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: NivaraColors.primary.withValues(alpha: 0.15),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.mic_rounded,
                color: NivaraColors.primary,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                widget.tooltip ?? 'Voice Dictate',
                style: const TextStyle(
                  color: NivaraColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
