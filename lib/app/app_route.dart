/// Compile-time-checked route locations for go_router.
///
/// Nothing outside `router.dart` should build a path with a raw string —
/// construct one of these and read `.location` instead, so a typo or a
/// missing path parameter is a compile error, not a 404 at runtime.
sealed class AppRoute {
  const AppRoute();

  String get location;
}

final class LanguageRoute extends AppRoute {
  const LanguageRoute();

  static const name = 'language';

  @override
  String get location => '/language';
}

final class HomeRoute extends AppRoute {
  const HomeRoute();

  static const name = 'home';

  @override
  String get location => '/home';
}

final class JourneyRoute extends AppRoute {
  const JourneyRoute();

  static const name = 'journey';

  @override
  String get location => '/journey';
}

final class GameRoute extends AppRoute {
  const GameRoute(this.levelId);

  final String levelId;

  static const name = 'game';
  static const pathPattern = '/game/:levelId';

  @override
  String get location => '/game/$levelId';
}

final class DailyRoute extends AppRoute {
  const DailyRoute();

  static const name = 'daily';

  @override
  String get location => '/daily';
}

final class LeaderboardRoute extends AppRoute {
  const LeaderboardRoute();

  static const name = 'leaderboard';

  @override
  String get location => '/leaderboard';
}

final class ProfileRoute extends AppRoute {
  const ProfileRoute();

  static const name = 'profile';

  @override
  String get location => '/profile';
}

final class SettingsRoute extends AppRoute {
  const SettingsRoute();

  static const name = 'settings';

  @override
  String get location => '/settings';
}
