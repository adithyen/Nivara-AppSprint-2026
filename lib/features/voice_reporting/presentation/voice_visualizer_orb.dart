import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/voice_reporting_models.dart';

/// Emil-motion inspired pulsating cyber-voice orb with concentric energy rings
/// and a 7-band reactive equalizer waveform responding to live microphone decibels.
class VoiceVisualizerOrb extends StatefulWidget {
  final VoiceState state;
  final double soundLevel; // 0.0 to 10.0 or higher
  final VoidCallback? onTap;

  const VoiceVisualizerOrb({
    super.key,
    required this.state,
    required this.soundLevel,
    this.onTap,
  });

  @override
  State<VoiceVisualizerOrb> createState() => _VoiceVisualizerOrbState();
}

class _VoiceVisualizerOrbState extends State<VoiceVisualizerOrb>
    with TickerProviderStateMixin {
  late AnimationController _ambientPulseController;
  late Animation<double> _ambientScaleAnimation;

  // 7-band equalizer random seeds for natural physical fluid oscillation
  final List<double> _barMultipliers = [0.4, 0.7, 1.0, 1.3, 0.9, 0.6, 0.35];

  @override
  void initState() {
    super.initState();
    // Ambient breathing loop
    _ambientPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _ambientScaleAnimation = CurvedAnimation(
      parent: _ambientPulseController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _ambientPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isListening = widget.state == VoiceState.listening;
    final isProcessing = widget.state == VoiceState.processing;

    // Map decibels to physical scale jump
    final dynamicBoost = (widget.soundLevel.clamp(0.0, 10.0) / 10.0);
    final currentScale = 1.0 + (isListening ? dynamicBoost * 0.28 : 0.0);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ambientPulseController,
        builder: (context, child) {
          final breath = _ambientScaleAnimation.value;

          return SizedBox(
            width: 170,
            height: 170,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer Ripple Ring 3
                if (isListening)
                  Transform.scale(
                    scale: (1.0 + (breath * 0.15) + (dynamicBoost * 0.38)).clamp(0.9, 1.6),
                    child: Container(
                      width: 154,
                      height: 154,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00FFCC).withValues(alpha: 0.18),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                // Outer Ripple Ring 2
                Transform.scale(
                  scale: (0.94 + (breath * 0.08) + (isListening ? dynamicBoost * 0.22 : 0.0)),
                  child: Container(
                    width: 126,
                    height: 126,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0284C7).withValues(alpha: isListening ? 0.35 : 0.2),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isListening ? const Color(0xFF00FFCC) : NivaraColors.primary)
                              .withValues(alpha: isListening ? 0.25 : 0.12),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),

                // Center Main Glowing Glass Orb
                Transform.scale(
                  scale: currentScale,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isListening
                            ? const [Color(0xFF00FFCC), Color(0xFF0284C7)]
                            : (isProcessing
                                ? const [Color(0xFFF59E0B), Color(0xFFEA580C)]
                                : const [Color(0xFF1E293B), Color(0xFF0F172A)]),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isListening
                              ? const Color(0xFF00FFCC).withValues(alpha: 0.45)
                              : Colors.black45,
                          blurRadius: isListening ? 22 : 12,
                          spreadRadius: isListening ? 2 : 0,
                        ),
                      ],
                    ),
                    child: Center(
                      child: isProcessing
                          ? const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                          : (isListening
                              ? _buildEqualizerWaveform(dynamicBoost)
                              : const Icon(
                                  Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 40,
                                )),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Builds a 7-band reactive vertical equalizer responding to sound energy
  Widget _buildEqualizerWaveform(double boost) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(7, (i) {
        final multiplier = _barMultipliers[i];
        final minHeight = 8.0;
        final maxHeight = 42.0;
        final targetHeight = (minHeight + (boost * maxHeight * multiplier)).clamp(minHeight, maxHeight);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOutBack,
          margin: const EdgeInsets.symmetric(horizontal: 2.2),
          width: 4.2,
          height: targetHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.6),
                blurRadius: 4,
              ),
            ],
          ),
        );
      }),
    );
  }
}
