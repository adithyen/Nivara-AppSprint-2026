import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bouncy_tap.dart';

/// Interactive info guide sheet that auto-pops until the user explicitly checks
/// "I understand how this works" and drags a physical spring slide-to-confirm
/// widget ("Understood, don't show again").
class InteractiveInfoGuideSheet extends StatefulWidget {
  final String preferenceKey;
  final Widget icon;
  final String title;
  final String subtitle;
  final List<GuideInfoCardItem> items;
  final String actionLabel;
  final VoidCallback? onActionTap;
  final Widget? customHeader;

  const InteractiveInfoGuideSheet({
    super.key,
    required this.preferenceKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.items,
    this.actionLabel = 'Get Started',
    this.onActionTap,
    this.customHeader,
  });

  static Future<void> show(
    BuildContext context, {
    required String preferenceKey,
    required Widget icon,
    required String title,
    required String subtitle,
    required List<GuideInfoCardItem> items,
    String actionLabel = 'Get Started',
    VoidCallback? onActionTap,
    Widget? customHeader,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      builder: (_) => InteractiveInfoGuideSheet(
        preferenceKey: preferenceKey,
        icon: icon,
        title: title,
        subtitle: subtitle,
        items: items,
        actionLabel: actionLabel,
        onActionTap: onActionTap,
        customHeader: customHeader,
      ),
    );
  }

  @override
  State<InteractiveInfoGuideSheet> createState() => _InteractiveInfoGuideSheetState();
}

class _InteractiveInfoGuideSheetState extends State<InteractiveInfoGuideSheet>
    with SingleTickerProviderStateMixin {
  bool _isChecked = false;
  bool _isAcknowledgedPermanently = false;

  Future<void> _onPermanentlyAcknowledged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.preferenceKey, true);
    if (!mounted) return;
    setState(() => _isAcknowledgedPermanently = true);
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 320));
    if (mounted) {
      Navigator.of(context).pop();
      widget.onActionTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Glowing Icon Header
              Center(child: widget.icon),
              const SizedBox(height: 16),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              if (widget.customHeader != null) ...[
                widget.customHeader!,
                const SizedBox(height: 16),
              ],

              // Informative Cards
              for (final item in widget.items) ...[
                _GuideInfoCard(item: item),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 14),

              // "I understand how this works" Checkbox with Tactile Physics
              BouncyTap(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isChecked = !_isChecked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isChecked
                        ? (_isDarkNeon(isDark)
                            ? const Color(0xFF00FFCC).withValues(alpha: 0.12)
                            : const Color(0xFF00BFA5).withValues(alpha: 0.12))
                        : (isDark ? const Color(0xFF161F2C) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isChecked
                          ? const Color(0xFF00FFCC).withValues(alpha: 0.6)
                          : (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0)),
                      width: _isChecked ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutBack,
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _isChecked
                              ? const Color(0xFF00FFCC)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isChecked
                                ? const Color(0xFF00FFCC)
                                : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                            width: 2,
                          ),
                        ),
                        child: _isChecked
                            ? const Icon(Icons.check_rounded, size: 16, color: Colors.black)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'I understand how this works',
                              style: TextStyle(
                                color: primaryText,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              'Check to unlock the permanent acknowledgment slider',
                              style: TextStyle(
                                color: secondaryText,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Animated Slide-To-Confirm Slider with Emil Kowalski Spring Dynamics
              AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                child: _isChecked
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SlideToConfirm(
                          isConfirmed: _isAcknowledgedPermanently,
                          label: 'Slide: Understood, don\'t show again',
                          onConfirmed: _onPermanentlyAcknowledged,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // Standard Dismiss / Proceed Action
              if (!_isAcknowledgedPermanently)
                BouncyTap(
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onActionTap?.call();
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        widget.actionLabel,
                        style: TextStyle(
                          color: primaryText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isDarkNeon(bool isDark) => isDark;
}

class GuideInfoCardItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final Widget? trailingBadge;

  const GuideInfoCardItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.trailingBadge,
  });
}

class _GuideInfoCard extends StatelessWidget {
  final GuideInfoCardItem item;

  const _GuideInfoCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131A24) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.iconColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, size: 20, color: item.iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (item.trailingBadge != null) ...[
                      const SizedBox(width: 6),
                      item.trailingBadge!,
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.description,
                  style: TextStyle(
                    color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B),
                    fontSize: 11.5,
                    height: 1.35,
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

/// Tactile Slide-To-Confirm widget powered by Emil Kowalski physical spring return.
class _SlideToConfirm extends StatefulWidget {
  final String label;
  final bool isConfirmed;
  final VoidCallback onConfirmed;

  const _SlideToConfirm({
    required this.label,
    required this.isConfirmed,
    required this.onConfirmed,
  });

  @override
  State<_SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<_SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  late AnimationController _springController;
  late Animation<double> _springAnimation;

  static const double _thumbWidth = 50.0;
  static const double _height = 54.0;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double maxDrag) {
    if (widget.isConfirmed) return;
    setState(() {
      _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, maxDrag);
    });
    if (_dragPosition >= maxDrag * 0.9) {
      HapticFeedback.lightImpact();
    }
  }

  void _onDragEnd(DragEndDetails details, double maxDrag) {
    if (widget.isConfirmed) return;
    if (_dragPosition >= maxDrag * 0.85) {
      // Complete confirmation
      setState(() => _dragPosition = maxDrag);
      widget.onConfirmed();
    } else {
      // Spring bounce back using physical spring dynamics
      _springAnimation = Tween<double>(
        begin: _dragPosition,
        end: 0.0,
      ).animate(
        CurvedAnimation(
          parent: _springController,
          curve: Curves.elasticOut,
        ),
      );
      _springController.reset();
      _springAnimation.addListener(() {
        setState(() => _dragPosition = _springAnimation.value);
      });
      _springController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth - _thumbWidth - 8.0;
        final progress = maxDrag > 0 ? (_dragPosition / maxDrag).clamp(0.0, 1.0) : 0.0;

        return Container(
          height: _height,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF090D14) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: widget.isConfirmed
                  ? const Color(0xFF00FFCC)
                  : const Color(0xFF00FFCC).withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Filled Progress Gradient Track
              Container(
                width: _thumbWidth + (maxDrag * progress),
                height: _height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00FFCC).withValues(alpha: 0.25),
                      const Color(0xFF00BFA5).withValues(alpha: 0.45),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),

              // Centered Prompt Label
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    widget.isConfirmed ? '✓ Confirmed — never showing again' : widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isConfirmed
                          ? const Color(0xFF00FFCC)
                          : (isDark ? Colors.white70 : const Color(0xFF334155)),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),

              // Draggable Physical Thumb
              Positioned(
                left: 4.0 + _dragPosition,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) => _onDragUpdate(details, maxDrag),
                  onHorizontalDragEnd: (details) => _onDragEnd(details, maxDrag),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: _thumbWidth,
                    height: _thumbWidth,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: widget.isConfirmed
                            ? [const Color(0xFF00FFCC), const Color(0xFF00BFA5)]
                            : [const Color(0xFF00FFCC), const Color(0xFF0284C7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FFCC).withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.isConfirmed ? Icons.check_rounded : Icons.arrow_forward_rounded,
                      color: Colors.black,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
