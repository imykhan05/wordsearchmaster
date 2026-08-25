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
import 'app_route.dart';

part 'router.g.dart';

/// The one and only [GoRouter]. FTUE starts at [LanguageRoute] (Chapter 02:
/// splash → language select, no login/permission/ad screens first).
@riverpod
GoRouter router(Ref ref) {
  return GoRouter(
    initialLocation: const LanguageRoute().location,
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
    ],
  );
}
