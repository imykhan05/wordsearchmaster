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
import '../presentation/screens/style_gallery_screen.dart';
import '../presentation/screens/sync_inspector_screen.dart';
import 'app_route.dart';
import 'config/app_config.dart';
import 'language/selected_language.dart';

part 'router.g.dart';

/// The one and only [GoRouter]. FTUE starts at [LanguageRoute] (Chapter 02:
/// splash → language select, no login/permission/ad screens first).
@riverpod
GoRouter router(Ref ref) {
  final isDev = ref.watch(appConfigProvider).flavor == Flavor.dev;

  // `read`, deliberately NOT `watch`. This decides where the app OPENS, and
  // nothing more. Watching it would rebuild the entire GoRouter the moment
  // the FTUE player taps a language card — flipping the provider false→true
  // mid-session and throwing the player out of the level that tap just
  // started. Read once, at construction, which is the only moment an
  // initial location means anything.
  final returning = ref.read(hasChosenLanguageProvider);

  return GoRouter(
    // Ch02's FTUE opens on the language picker; a player who has already
    // chosen lands on Home instead, where the journey map (every unlocked
    // level, forward and back), the daily, and collections are reachable.
    // Before this, every launch re-ran the picker and then `.go()`'d straight
    // into level 1 — which left the map and everything else unreachable, and
    // is why the app looked like it had no level select at all.
    initialLocation: returning
        ? const HomeRoute().location
        : const LanguageRoute().location,
    debugLogDiagnostics: false,
    routes: [
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
