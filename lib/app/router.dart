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

/// The one and only [GoRouter]. A launch opens on [LanguageRoute] the first
/// time and [HomeRoute] after that.
///
/// THERE IS NO SPLASH ROUTE. The splash now runs in front of `runApp`
/// entirely (`BootSplash`, mounted by `bootstrap.dart`'s `_BootGate`), so by
/// the time this router is built the app is already up and the only question
/// left is which screen to open on. Routing through a splash screen to answer
/// that would put a second one on screen after the first had just finished.
///
/// [hasChosenLanguageProvider] is READ, never watched, and that distinction
/// is the one this provider has always turned on: a watch rebuilds the whole
/// `GoRouter` the instant an FTUE player taps a language card, throwing them
/// out of whatever that tap just started. A read cannot, and here it cannot
/// even be stale — `_BootGate` does not build the app until the settings
/// store has resolved, so this value is final before anything can ask for it.
@riverpod
GoRouter router(Ref ref) {
  final isDev = ref.watch(appConfigProvider).flavor == Flavor.dev;
  final returning = ref.read(hasChosenLanguageProvider);

  return GoRouter(
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
