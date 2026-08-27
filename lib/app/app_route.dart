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

/// Today's puzzle itself, distinct from [DailyRoute] (the pre-game screen
/// showing "play" or today's already-recorded result). No path parameter —
/// unlike [GameRoute], WHICH day is a [GameSession] resolves at runtime via
/// `TrustedClock`, not something the URL should let a link encode (a
/// `/game/daily/2026-08-26` link would let a player jump straight to a day
/// that isn't today, defeating the one-attempt gate).
final class DailyGameRoute extends AppRoute {
  const DailyGameRoute();

  static const name = 'dailyGame';

  @override
  String get location => '/game/daily';
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

/// DEV FLAVOR ONLY — `router.dart` registers this route only when the running
/// flavor is [Flavor.dev], so navigating to it in stg/prod 404s by design.
final class StyleGalleryRoute extends AppRoute {
  const StyleGalleryRoute();

  static const name = 'styleGallery';

  @override
  String get location => '/dev/style-gallery';
}
