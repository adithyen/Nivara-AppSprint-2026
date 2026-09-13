import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/app_lock_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';

/// Full-screen overlay presented when the app is locked.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({
    super.key,
    required this.onUnlocked,
  });

  final VoidCallback onUnlocked;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> with SingleTickerProviderStateMixin {
  bool _isAuthenticating = false;
  String? _errorMessage;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Auto-trigger biometric prompt after layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAuth();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _triggerAuth() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final success = await AppLockService.instance.authenticate(
      localizedReason: 'Unlock Nivara using your fingerprint, face, or phone passcode',
    );

    if (!mounted) return;
    setState(() => _isAuthenticating = false);

    if (success) {
      HapticFeedback.mediumImpact();
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _errorMessage = 'Authentication cancelled or failed. Tap below to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // Prevent back navigation while locked
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF090D14) : const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Animated Pulsing Biometric Shield
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1.0 + (_pulseController.value * 0.08);
                    final glowOpacity = 0.2 + (_pulseController.value * 0.25);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00FFCC), Color(0xFF0091FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00FFCC).withValues(alpha: glowOpacity),
                              blurRadius: 30,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.fingerprint_rounded,
                          size: 56,
                          color: Colors.black,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 36),

                Text(
                  'Nivara is Locked',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Protected by device biometric & phone passcode security.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: NivaraColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NivaraColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: NivaraColors.danger,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const Spacer(),

                // Unlock Button
                BouncyTap(
                  onTap: _triggerAuth,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00FFCC), Color(0xFF00E5FF)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FFCC).withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_open_rounded, color: Colors.black, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _isAuthenticating ? 'Authenticating...' : 'Unlock with Biometrics / PIN',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Prompt shown once to fresh users asking if they want to turn on App Lock.
Future<bool?> showFreshAppLockSetupDialog(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: isDark ? const Color(0xFF101622) : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00FFCC).withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.security_rounded,
                  size: 40,
                  color: Color(0xFF00FFCC),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Enable Biometric App Lock?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Protect your civic activity, reports, and identity. Open Nivara securely using Fingerprint, Face ID, or your phone passcode.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              BouncyTap(
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  await AppLockService.instance.markPrompted();
                  final success = await AppLockService.instance.authenticate(
                    localizedReason: 'Verify to activate App Lock on Nivara',
                  );
                  if (success) {
                    await AppLockService.instance.setLockEnabled(true);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } else {
                    if (ctx.mounted) Navigator.pop(ctx, false);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00FFCC), Color(0xFF00E5FF)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(
                    child: Text(
                      'Turn ON App Lock',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  await AppLockService.instance.markPrompted();
                  await AppLockService.instance.setLockEnabled(false);
                  if (ctx.mounted) Navigator.pop(ctx, false);
                },
                child: Text(
                  'Not Now (You can enable later in Profile)',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
