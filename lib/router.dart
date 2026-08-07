import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/admin/admin_dashboard.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/home/home_screen.dart';

/// App routes. Kept as plain string constants so redirects and navigation
/// don't drift apart.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const home = '/home';
  static const admin = '/admin';
}

/// The single [GoRouter] instance, built with an auth/role redirect guard.
///
/// The guard reads [authControllerProvider]; a [ValueNotifier] bumped on every
/// auth change is wired to [GoRouter.refreshListenable] so redirects re-run
/// whenever the user signs in/out or their profile finishes loading.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final atAuth = loc == Routes.login || loc == Routes.signup;
      final atSplash = loc == Routes.splash;

      // Initial profile still loading — hold on the splash screen.
      if (auth.isLoading) return atSplash ? null : Routes.splash;

      final profile = auth.asData?.value;
      final loggedIn = profile != null;

      if (!loggedIn) return atAuth ? null : Routes.login;

      // Logged in: send splash/auth traffic to the role's landing screen.
      final landing = profile.isAdmin ? Routes.admin : Routes.home;
      if (atAuth || atSplash) return landing;

      // Citizens can't reach the municipal side.
      if (loc.startsWith(Routes.admin) && !profile.isAdmin) return Routes.home;

      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.admin,
        builder: (context, state) => const AdminDashboard(),
      ),
    ],
  );
});
