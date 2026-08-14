import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../router.dart';
import 'auth_controller.dart';

/// Email + password sign-in. Navigation on success is handled by the router's
/// redirect guard — this screen only drives the form + error display.
///
/// The role toggle (Citizen / Officials) reveals + prefills the demo
/// credentials for each side so testers can walk the full round-trip without
/// setting up separate accounts. Field workers log in here too (using their
/// assigned credentials).
enum _LoginMode { citizen, official }

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
      // Clear any previously prefilled demo value before applying the new one.
      const demoUsers = [kDemoAdminUsername];
      const demoPasswords = [kDemoAdminPassword];
      if (demoUsers.contains(_email.text)) _email.clear();
      if (demoPasswords.contains(_password.text)) _password.clear();
      switch (mode) {
        case _LoginMode.citizen:
          break;
        case _LoginMode.official:
          _email.text = kDemoAdminUsername;
          _password.text = kDemoAdminPassword;
      }
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
      // Demo admin sign in with a username alias; map it to the real email.
      final lower = raw.toLowerCase();
      final email = lower == kDemoAdminUsername
          ? kDemoAdminEmail
          : raw;
      await ref
          .read(authControllerProvider.notifier)
          .signIn(email: email, password: _password.text);
      // Redirect guard navigates away on success.
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
    final isStaff = _mode != _LoginMode.citizen;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.location_city,
                    size: 56,
                    color: NivaraColors.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    kAppName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kAppTagline,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SegmentedButton<_LoginMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _LoginMode.citizen,
                        label: Text('Citizen'),
                        icon: Icon(Icons.person_outline),
                      ),
                      ButtonSegment(
                        value: _LoginMode.official,
                        label: Text('Officials'),
                        icon: Icon(Icons.shield_outlined),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: _loading
                        ? null
                        : (s) => _setMode(s.first),
                  ),
                  if (isStaff) ...[
                    const SizedBox(height: 16),
                    _DemoStaffCard(mode: _mode),
                  ],
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _email,
                    keyboardType: isStaff
                        ? TextInputType.text
                        : TextInputType.emailAddress,
                    autofillHints: isStaff ? null : const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: isStaff ? 'Email or username' : 'Email',
                      prefixIcon: Icon(
                        isStaff ? Icons.badge_outlined : Icons.email_outlined,
                      ),
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return 'Enter your email';
                      final lower = t.toLowerCase();
                      if (lower == kDemoAdminUsername) return null;
                      if (!t.contains('@') || !t.contains('.')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: isStaff
                        ? null
                        : const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(switch (_mode) {
                            _LoginMode.citizen => 'Sign in',
                            _LoginMode.official => 'Sign in as official',
                          }),
                  ),
                  const SizedBox(height: 8),
                  if (!isStaff)
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => context.go(Routes.signup),
                      child: const Text("Don't have an account? Sign up"),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the prefilled demo credentials for the selected staff role.
class _DemoStaffCard extends StatelessWidget {
  const _DemoStaffCard({required this.mode});
  final _LoginMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo official (prefilled)',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Username: $kDemoAdminUsername\nPassword: $kDemoAdminPassword',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Field workers: use your assigned email (e.g. pothole_worker1@nivara.app) with password worker123',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.8),
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
