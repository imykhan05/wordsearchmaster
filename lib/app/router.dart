import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../presentation/screens/daily_screen.dart';
import '../presentation/screens/game_screen.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/screens/journey_screen.dart';
import '../presentation/screens/language_screen.dart';
import '../presentation/screens/leaderboard_screen.dart';
import '../presentation/screens/profile_screen.dart';
import '../presentation/screens/settings_screen.dart';
import '../presentation/screens/splash_screen.dart';
import '../presentation/screens/style_gallery_screen.dart';
import '../presentation/screens/sync_inspector_screen.dart';
import 'app_route.dart';
import 'config/app_config.dart';

part 'router.g.dart';

/// The one and only [GoRouter]. Every launch opens on [SplashRoute] —
/// `splash_screen.dart` is the one place that reads `hasChosenLanguageProvider`
/// now, and it does so ONCE, right before its own one-shot navigation to
/// [LanguageRoute] (FTUE) or [HomeRoute] (returning). That is a deliberate
/// move from the previous shape, where THIS provider built the router's
/// `initialLocation` directly: reading it here meant `routerProvider` itself
/// depended on player state, which is exactly the kind of dependency the
/// removed `read`-not-`watch` comment used to have to justify so carefully.
/// Now the router depends on nothing but the flavor — it cannot be rebuilt
/// out from under a running session by ANY change to that provider, because
/// it never reads it at all.
@riverpod
GoRouter router(Ref ref) {
  final isDev = ref.watch(appConfigProvider).flavor == Flavor.dev;

  return GoRouter(
    initialLocation: const SplashRoute().location,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: const SplashRoute().location,
        name: SplashRoute.name,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: const LanguageRoute().location,
        name: LanguageRoute.name,
        builder: (context, state) => const LanguageScreen(),
      ),
      GoRoute(
        path: const HomeRoute().location,
        name: HomeRoute.name,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: const JourneyRoute().location,
        name: JourneyRoute.name,
        builder: (context, state) => const JourneyScreen(),
      ),
      // Registered BEFORE GameRoute: go_router matches route entries in
      // order, and GameRoute's `/game/:levelId` pattern would otherwise also
      // match this literal path, treating "daily" as a level id.
      GoRoute(
        path: const DailyGameRoute().location,
        name: DailyGameRoute.name,
        builder: (context, state) => const GameScreen.daily(),
      ),
      GoRoute(
        path: GameRoute.pathPattern,
        name: GameRoute.name,
        builder: (context, state) =>
            GameScreen(levelId: state.pathParameters['levelId']!),
      ),
      GoRoute(
        path: const DailyRoute().location,
        name: DailyRoute.name,
        builder: (context, state) => const DailyScreen(),
      ),
      GoRoute(
        path: const LeaderboardRoute().location,
        name: LeaderboardRoute.name,
        builder: (context, state) => const LeaderboardScreen(),
      ),
      GoRoute(
        path: const ProfileRoute().location,
        name: ProfileRoute.name,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: const SettingsRoute().location,
        name: SettingsRoute.name,
        builder: (context, state) => const SettingsScreen(),
      ),
      // Dev-only tooling. Absent from the route table entirely on stg/prod,
      // rather than gated inside the screen — there is no build in which a
      // player can reach it.
      if (isDev) ...[
        GoRoute(
          path: const StyleGalleryRoute().location,
          name: StyleGalleryRoute.name,
          builder: (context, state) => const StyleGalleryScreen(),
        ),
        GoRoute(
          path: const SyncInspectorRoute().location,
          name: SyncInspectorRoute.name,
          builder: (context, state) => const SyncInspectorScreen(),
        ),
      ],
    ],
  );
}
