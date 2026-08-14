import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/activity/activity_log_screen.dart';
import 'features/activity/pending_sync_screen.dart';
import 'features/admin/admin_report_detail.dart';
import 'features/admin/admin_shell.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/community/community_compose_screen.dart';
import 'features/home/home_shell.dart';
import 'features/lostfound/lostfound_hub.dart';
import 'features/lostfound/lf_item_detail.dart';
import 'features/lostfound/my_listings_screen.dart';
import 'features/lostfound/match_screen.dart';
import 'features/lostfound/report_found_screen.dart';
import 'features/lostfound/report_lost_screen.dart';
import 'features/map/civic_map.dart';
import 'features/map/location_picker_screen.dart';
import 'features/report/report_detail_screen.dart';
import 'features/report/report_form_screen.dart';
import 'features/sensorwatch/sensor_watch_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/home/worker_shell.dart';
import 'features/worker/worker_task_detail.dart';
import 'models/community_post.dart';
import 'models/enums.dart';
import 'models/lf_item.dart';
import 'models/report.dart';

/// App routes. Kept as plain string constants so redirects and navigation
/// don't drift apart.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const home = '/home';
  static const sensorWatch = '/sensorwatch';
  static const report = '/report';
  static const reportDetail = '/report/detail';
  static const map = '/map';
  static const lostFound = '/lostfound';
  static const reportLost = '/lostfound/lost';
  static const reportFound = '/lostfound/found';
  static const lostFoundMatch = '/lostfound/match';
  static const lostFoundDetail = '/lostfound/detail';
  static const myListings = '/lostfound/mine';
  static const communityCompose = '/community/compose';
  static const settings = '/settings';
  static const worker = '/worker';
  static const workerTask = '/worker/task';
  static const admin = '/admin';
  static const adminReportDetail = '/admin/report';
  static const activityLog = '/activity';
  static const pendingSync = '/activity/sync';
  static const locationPicker = '/map/picker';
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
      final landing = profile.isAdmin
          ? Routes.admin
          : profile.isWorker
          ? Routes.worker
          : Routes.home;
      if (atAuth || atSplash) return landing;

      // Keep admins on /admin, workers on /worker — but workers CAN navigate
      // to citizen sub-routes (map, report form, L&F, community, etc.).
      if (loc.startsWith(Routes.admin) && !profile.isAdmin) return landing;
      // Only block workers from landing on /admin, not from citizen routes.
      if (loc == Routes.worker && !profile.isWorker && !profile.isAdmin) return landing;

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
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: Routes.sensorWatch,
        builder: (context, state) => const SensorWatchScreen(),
      ),
      GoRoute(
        path: Routes.report,
        builder: (context, state) => const ReportFormScreen(),
      ),
      GoRoute(
        path: Routes.reportDetail,
        builder: (context, state) =>
            ReportDetailScreen(report: state.extra as Report),
      ),
      GoRoute(
        path: Routes.map,
        builder: (context, state) => const CivicMapScreen(),
      ),
      GoRoute(
        path: Routes.lostFound,
        builder: (context, state) => const LostFoundHub(),
      ),
      GoRoute(
        path: Routes.myListings,
        builder: (context, state) => const MyListingsScreen(),
      ),
      GoRoute(
        path: Routes.reportLost,
        builder: (context, state) => const ReportLostScreen(),
      ),
      GoRoute(
        path: Routes.reportFound,
        builder: (context, state) => const ReportFoundScreen(),
      ),
      GoRoute(
        path: Routes.lostFoundMatch,
        builder: (context, state) => MatchScreen(item: state.extra as LFItem),
      ),
      GoRoute(
        path: Routes.lostFoundDetail,
        builder: (context, state) {
          // extra is a record: (item, distanceMeters, isMatch). Hub taps pass a
          // bare LFItem; normalise both.
          final extra = state.extra;
          if (extra is LFItem) {
            return LFItemDetailScreen(item: extra);
          }
          final args = extra as ({LFItem item, double? distance, bool isMatch});
          return LFItemDetailScreen(
            item: args.item,
            distanceMeters: args.distance,
            isMatch: args.isMatch,
          );
        },
      ),
      GoRoute(
        path: Routes.communityCompose,
        builder: (context, state) {
          final args =
              state.extra
                  as ({CommunityPostType type, CommunityPost? existing});
          return CommunityComposeScreen(
            type: args.type,
            existing: args.existing,
          );
        },
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.worker,
        builder: (context, state) => const WorkerShell(),
      ),
      GoRoute(
        path: Routes.workerTask,
        builder: (context, state) =>
            WorkerTaskDetailScreen(report: state.extra as Report),
      ),
      GoRoute(
        path: Routes.admin,
        builder: (context, state) => const AdminShell(),
      ),
      GoRoute(
        path: Routes.adminReportDetail,
        builder: (context, state) =>
            AdminReportDetailScreen(report: state.extra as Report),
      ),
      GoRoute(
        path: Routes.activityLog,
        builder: (context, state) => const ActivityLogScreen(),
      ),
      GoRoute(
        path: Routes.pendingSync,
        builder: (context, state) => const PendingSyncScreen(),
      ),
      GoRoute(
        path: Routes.locationPicker,
        builder: (context, state) => const LocationPickerScreen(),
      ),
    ],
  );
});
