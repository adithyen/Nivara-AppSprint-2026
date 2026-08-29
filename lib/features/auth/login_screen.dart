import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/glass_card.dart';
import '../../router.dart';
import 'auth_controller.dart';

enum _LoginMode { citizen, worker, official }

/// 2026-Level Cyber-Civic Portal Login Screen.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  _LoginMode _mode = _LoginMode.citizen;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _setMode(_LoginMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      switch (mode) {
        case _LoginMode.citizen:
          _email.clear();
          _password.clear();
          break;
        case _LoginMode.worker:
          _email.text = 'pothole_worker1@nivara.app';
          _password.text = 'worker123';
          break;
        case _LoginMode.official:
          _email.text = kDemoAdminEmail;
          _password.text = kDemoAdminPassword;
          break;
      }
    });
  }

  void _fillWorker({required String email, required String password}) {
    setState(() {
      _email.text = email;
      _password.text = password;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = _email.text.trim();
      final lower = raw.toLowerCase();
      String email = raw;
      if (lower == kDemoAdminUsername || lower == 'admin') {
        email = kDemoAdminEmail;
      } else if (lower == kDemoWorkerUsername || lower == 'worker') {
        email = kDemoWorkerEmail;
      } else if (!raw.contains('@')) {
        email = '$raw@nivara.app';
      }

      await ref
          .read(authControllerProvider.notifier)
          .signIn(email: email, password: _password.text.trim());
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isStaff = _mode != _LoginMode.citizen;

    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B);
    final iconColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: isDark ? NivaraColors.canvasDark : NivaraColors.surfaceLight,
      body: Stack(
        children: [
          // Background ambient gradient orbs
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NivaraColors.primary.withValues(alpha: isDark ? 0.12 : 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NivaraColors.primaryBlue.withValues(alpha: isDark ? 0.08 : 0.06),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Glowing Brand Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E676).withValues(alpha: isDark ? 0.4 : 0.25),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_city_rounded,
                          size: 40,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        kAppName,
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        kAppTagline,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 3-Way Role Switcher
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF10161E) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _buildRoleTab(
                              mode: _LoginMode.citizen,
                              label: 'Citizen',
                              icon: Icons.person_rounded,
                              activeColor: NivaraColors.primary,
                              isDark: isDark,
                              iconColor: iconColor,
                            ),
                            _buildRoleTab(
                              mode: _LoginMode.worker,
                              label: 'Worker',
                              icon: Icons.engineering_rounded,
                              activeColor: const Color(0xFF00B0FF),
                              isDark: isDark,
                              iconColor: iconColor,
                            ),
                            _buildRoleTab(
                              mode: _LoginMode.official,
                              label: 'Officials',
                              icon: Icons.shield_rounded,
                              activeColor: NivaraColors.accent,
                              isDark: isDark,
                              iconColor: iconColor,
                            ),
                          ],
                        ),
                      ),

                      if (_mode == _LoginMode.worker) ...[
                        const SizedBox(height: 16),
                        _WorkerDemoBox(
                          currentEmail: _email.text.trim(),
                          onSelect: _fillWorker,
                        ),
                      ] else if (_mode == _LoginMode.official) ...[
                        const SizedBox(height: 16),
                        const _OfficialDemoBox(),
                      ],

                      const SizedBox(height: 20),

                      // Email / Username input
                      TextFormField(
                        controller: _email,
                        keyboardType: isStaff
                            ? TextInputType.text
                            : TextInputType.emailAddress,
                        autofillHints: isStaff ? null : const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        style: TextStyle(color: primaryText, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: isStaff ? 'Email or worker username' : 'Email',
                          prefixIcon: Icon(
                            isStaff ? Icons.badge_outlined : Icons.email_outlined,
                            color: iconColor,
                          ),
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'Enter your email or username';
                          final lower = t.toLowerCase();
                          if (lower == kDemoAdminUsername ||
                              lower == kDemoWorkerUsername ||
                              lower.contains('_worker')) {
                            return null;
                          }
                          if (!t.contains('@') && !t.contains('_')) {
                            return 'Enter a valid email or worker alias';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Password input
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: isStaff
                            ? null
                            : const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        style: TextStyle(color: primaryText, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline, color: iconColor),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: iconColor,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: NivaraColors.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: NivaraColors.danger.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: NivaraColors.danger,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: NivaraColors.danger,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Gradient Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E676).withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.black,
                                    ),
                                  )
                                : Text(
                                    switch (_mode) {
                                      _LoginMode.citizen => 'Sign In as Citizen',
                                      _LoginMode.worker => 'Sign In as Field Worker',
                                      _LoginMode.official => 'Enter Command Portal',
                                    },
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Create Account Link
                      if (!isStaff)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account? ",
                              style: TextStyle(
                                color: secondaryText,
                                fontSize: 13.5,
                              ),
                            ),
                            TextButton(
                              onPressed: _loading ? null : () => context.go(Routes.signup),
                              child: Text(
                                'Sign Up',
                                style: TextStyle(
                                  color: isDark ? NivaraColors.primary : const Color(0xFF007A3D),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleTab({
    required _LoginMode mode,
    required String label,
    required IconData icon,
    required Color activeColor,
    required bool isDark,
    required Color iconColor,
  }) {
    final active = _mode == mode;
    return Expanded(
      child: BouncyTap(
        onTap: _loading ? null : () => _setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? activeColor.withValues(alpha: isDark ? 0.2 : 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: active
                ? Border.all(color: activeColor.withValues(alpha: 0.7))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: active ? activeColor : iconColor,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: active ? activeColor : iconColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stylized labeled card detailing worker username/password logic and 3 quick-fill examples.
class _WorkerDemoBox extends StatelessWidget {
  const _WorkerDemoBox({
    required this.currentEmail,
    required this.onSelect,
  });

  final String currentEmail;
  final void Function({required String email, required String password}) onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final examples = [
      (
        title: 'Pothole Worker #1',
        dept: 'Roads Dept',
        email: 'pothole_worker1@nivara.app',
        icon: Icons.edit_road_rounded,
        color: const Color(0xFFFF9100),
      ),
      (
        title: 'Street Light Worker #1',
        dept: 'Electricity Dept',
        email: 'street_light_worker1@nivara.app',
        icon: Icons.lightbulb_rounded,
        color: const Color(0xFFFFD600),
      ),
      (
        title: 'Garbage Worker #1',
        dept: 'Sanitation Dept',
        email: 'garbage_worker1@nivara.app',
        icon: Icons.delete_sweep_rounded,
        color: const Color(0xFF00E676),
      ),
    ];

    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      borderColor: const Color(0xFF00B0FF).withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B0FF).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.engineering_rounded,
                  color: Color(0xFF00B0FF),
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Worker Login Format & Demo Credentials',
                  style: TextStyle(
                    color: Color(0xFF00B0FF),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF080D14) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFCBD5E1),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Format: <category_key>_worker<1-5>@nivara.app',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Default Password: worker123',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tap any example below to 1-tap prefill and test:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final ex in examples) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: BouncyTap(
                onTap: () => onSelect(email: ex.email, password: 'worker123'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: currentEmail == ex.email
                        ? ex.color.withValues(alpha: isDark ? 0.2 : 0.14)
                        : (isDark ? const Color(0xFF141C26) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: currentEmail == ex.email
                          ? ex.color
                          : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      width: currentEmail == ex.email ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(ex.icon, color: ex.color, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ex.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                                color: currentEmail == ex.email ? ex.color : null,
                              ),
                            ),
                            Text(
                              '${ex.dept} • ${ex.email}',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (currentEmail == ex.email)
                        Icon(Icons.check_circle_rounded, color: ex.color, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfficialDemoBox extends StatelessWidget {
  const _OfficialDemoBox();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      borderColor: NivaraColors.accent.withValues(alpha: 0.35),
      child: const Row(
        children: [
          Icon(Icons.shield_rounded, color: NivaraColors.accent, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Municipal Official Pre-filled (admin@nivara.app)',
                  style: TextStyle(
                    color: NivaraColors.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Password: admin123 • Full command & dispatch authority',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
