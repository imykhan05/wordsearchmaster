import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The three build flavors. Each has its own Firebase project, its own
/// applicationId (via Gradle suffix), and never shares ad units with prod.
/// See CLAUDE.md → Flavors.
enum Flavor { dev, stg, prod }

/// Console verbosity for [AppConfig.logLevel]. Lower index = more verbose.
enum AppLogLevel { debug, info, warning, error }

/// Everything that differs between dev/stg/prod, resolved once at app start
/// and threaded through the widget tree via [appConfigProvider]. Nothing in
/// the app should branch on `kDebugMode` or a hardcoded flavor string —
/// branch on this instead.
final class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.firebaseOptions,
    required this.adsTestMode,
    required this.logLevel,
  });

  factory AppConfig.dev() => const AppConfig(
    flavor: Flavor.dev,
    // TODO(P13): wire via `flutterfire configure --project wsm-dev`.
    firebaseOptions: null,
    adsTestMode: true,
    logLevel: AppLogLevel.debug,
  );

  factory AppConfig.stg() => const AppConfig(
    flavor: Flavor.stg,
    // TODO(P13): wire via `flutterfire configure --project wsm-stg`.
    firebaseOptions: null,
    adsTestMode: true,
    logLevel: AppLogLevel.info,
  );

  factory AppConfig.prod() => const AppConfig(
    flavor: Flavor.prod,
    // TODO(P13): wire via `flutterfire configure --project wsm-prod`.
    firebaseOptions: null,
    adsTestMode: false,
    logLevel: AppLogLevel.warning,
  );

  final Flavor flavor;
  final FirebaseOptions? firebaseOptions;

  /// True on dev/stg. When true, [services/ads] must only ever request MAX
  /// test-mode ad units — never a real one. See CLAUDE.md → Never do.
  final bool adsTestMode;
  final AppLogLevel logLevel;

  String get flavorName => flavor.name.toUpperCase();
}

/// Overridden with the flavor-specific [AppConfig] in every `main_*.dart`.
/// Reading this before that override is a programming error, not a runtime
/// condition to handle gracefully — hence the throw rather than a default.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError(
    'appConfigProvider must be overridden in main_*.dart with the '
    'flavor-specific AppConfig.',
  ),
);
