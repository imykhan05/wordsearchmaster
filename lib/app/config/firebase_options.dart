/// Per-flavor Firebase project credentials (Ch13 / P13).
///
/// Three separate Firebase projects back the three flavors (CLAUDE.md →
/// Flavors): `wsm-dev-45b7c`, `wsm-stg-b1d5f`, `wsm-prod-a750e`. Each
/// per-flavor file (`firebase_options_{dev,stg,prod}.dart`) holds the values
/// from that project's `google-services.json`, copied in directly rather
/// than through a `flutterfire configure` run — see those files' own headers.
///
/// [forFlavor] can still return null for a flavor whose file has not been
/// populated (a fourth flavor added later, say): `bootstrap.dart` then skips
/// `Firebase.initializeApp` entirely and every Firebase-backed service keeps
/// its Noop binding, the same local-only mode a player in airplane mode gets
/// — tested by `bootstrap_offline_test.dart` rather than merely hoped for.
/// That is also why unpopulated flavors were left returning `null` rather
/// than fake-but-well-formed credentials while this was pending: a
/// placeholder key would compile and only fail at the first network call,
/// with an error that reads like an app bug rather than a missing setup
/// step — and could have shipped that way.
library;

import 'package:firebase_core/firebase_core.dart';

import 'app_config.dart';
import 'firebase_options_dev.dart';
import 'firebase_options_prod.dart';
import 'firebase_options_stg.dart';

/// Resolves the Firebase project for a flavor.
abstract final class FlavorFirebaseOptions {
  /// The credentials for [flavor], or null while its file is unpopulated.
  ///
  /// A null return is a supported state, not an error — see the library
  /// header. `bootstrap.dart` skips `Firebase.initializeApp` entirely and
  /// every Firebase-backed service keeps its Noop binding, which leaves a
  /// fully playable offline game.
  static FirebaseOptions? forFlavor(Flavor flavor) => switch (flavor) {
    Flavor.dev => DevFirebaseOptions.currentPlatform,
    Flavor.stg => StgFirebaseOptions.currentPlatform,
    Flavor.prod => ProdFirebaseOptions.currentPlatform,
  };

  /// Whether [flavor] has real credentials.
  ///
  /// Exists so the dev-flavor UI and the tests can SAY which mode the app is
  /// in rather than inferring it from a silent absence of cloud data — a
  /// developer who does not know Firebase is unconfigured will file the
  /// resulting "sync does nothing" as a bug.
  static bool isConfigured(Flavor flavor) => forFlavor(flavor) != null;

  /// The OAuth 2.0 **web** client id for [flavor]'s project, needed by
  /// Google Sign-In on Android so the id token it returns is minted for this
  /// Firebase project rather than for the app's own Android client.
  ///
  /// Copied from that project's `google-services.json`
  /// (`oauth_client` → the entry with `client_type: 3`), NOT from the Android
  /// client id — using the Android one is the single most common cause of
  /// `linkWithCredential` failing with an audience mismatch that reads like a
  /// generic sign-in error.
  ///
  /// Still null for all three flavors: each project's `oauth_client` list is
  /// currently empty, because Google Sign-In needs a SHA-1 (and SHA-256)
  /// certificate fingerprint registered on the Android app before Firebase
  /// will mint this client — see `docs/firebase-setup.md` §3. Guest play is
  /// unaffected; only the "sign in with Google" merge path needs this.
  static String? googleServerClientId(Flavor flavor) => switch (flavor) {
    // TODO(setup): paste each project's client_type 3 OAuth client id, once
    // a SHA-1 fingerprint has been registered and google-services.json
    // re-downloaded (docs/firebase-setup.md §3).
    Flavor.dev || Flavor.stg || Flavor.prod => null,
  };
}
