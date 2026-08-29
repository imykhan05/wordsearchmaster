import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';

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
    this.googleServerClientId,
  });

  /// Builds the config for [flavor], reading its Firebase credentials from
  /// [FlavorFirebaseOptions].
  ///
  /// One factory rather than three near-identical ones: the only things that
  /// actually differ per flavor are the two booleans and the log level, and
  /// three copies of the Firebase lookup was three places for it to drift.
  factory AppConfig.of(Flavor flavor) => AppConfig(
    flavor: flavor,
    firebaseOptions: FlavorFirebaseOptions.forFlavor(flavor),
    googleServerClientId: FlavorFirebaseOptions.googleServerClientId(flavor),
    adsTestMode: flavor != Flavor.prod,
    logLevel: switch (flavor) {
      Flavor.dev => AppLogLevel.debug,
      Flavor.stg => AppLogLevel.info,
      Flavor.prod => AppLogLevel.warning,
    },
  );

  factory AppConfig.dev() => AppConfig.of(Flavor.dev);

  factory AppConfig.stg() => AppConfig.of(Flavor.stg);

  factory AppConfig.prod() => AppConfig.of(Flavor.prod);

  final Flavor flavor;

  /// Null until `flutterfire configure` has been run for this flavor — see
  /// `firebase_options.dart`. A null here puts the app in local-only mode,
  /// which is a supported, tested state, not a failure.
  final FirebaseOptions? firebaseOptions;

  /// The OAuth web client id Google Sign-In needs on Android. Null alongside
  /// [firebaseOptions].
  final String? googleServerClientId;

  /// True on dev/stg. When true, [services/ads] must only ever request MAX
  /// test-mode ad units — never a real one. See CLAUDE.md → Never do.
  final bool adsTestMode;
  final AppLogLevel logLevel;

  /// Where P14's Cloud Functions live. Pinned because the client must call
  /// the SAME region the functions are deployed to: calling the default
  /// `us-central1` when they live in `asia-south1` fails at runtime with a
  /// CORS/404 that looks nothing like a region mismatch.
  ///
  /// `asia-south1` (Mumbai) is chosen for latency to the PK/IN audience this
  /// game targets (Ch01) — a round trip to Iowa is ~250ms of dead time on
  /// every score submission.
  static const String functionsRegion = 'asia-south1';

  /// Whether this build has real Firebase credentials.
  bool get isFirebaseConfigured => firebaseOptions != null;

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
