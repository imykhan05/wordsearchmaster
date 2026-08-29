import 'package:firebase_remote_config/firebase_remote_config.dart' as fb;

import '../diagnostics/error_reporter.dart';
import 'remote_config.dart';

/// The real [RemoteConfig], over Firebase Remote Config. The only file
/// allowed to import `firebase_remote_config`.
///
/// Fills in the binding `remote_config.dart` has carried a `TODO(P20)` for
/// since P11. P11 deliberately built the SHAPE — the typed key table with the
/// default and the sane range living on the key — precisely so that this file
/// could be one small adapter rather than a hunt for constants.
///
/// ---------------------------------------------------------------------------
/// A FETCHED VALUE IS CLAMPED, AND AN UNKNOWN KEY IS NOT ZERO
///
/// The second half matters more than it looks. `FirebaseRemoteConfig.getInt`
/// returns **0** for a key the console has never heard of — indistinguishable,
/// at the call site, from a console that deliberately set the value to 0. Take
/// that at face value and `hint_cost_coins` silently becomes free the first
/// time somebody renames a key, which is exactly the class of accident
/// `RemoteConfigKey.min` exists to stop.
///
/// So [getInt] checks the value's SOURCE first: anything that did not come
/// from the console or from the SDK's registered defaults resolves to the
/// key's own shipped default instead. Only a real, sourced value is clamped
/// and used.
final class FirebaseRemoteConfigAdapter implements RemoteConfig {
  const FirebaseRemoteConfigAdapter(this._config);

  final fb.FirebaseRemoteConfig _config;

  /// Ch13's budget: bootstrap waits at most this long for a fetch before
  /// carrying on with defaults. A first launch on a bad connection must not
  /// hold the first frame hostage.
  static const Duration fetchTimeout = Duration(seconds: 3);

  @override
  int getInt(RemoteConfigKey key) {
    try {
      final value = _config.getValue(key.name);
      // `valueStatic` is the SDK's "I have never heard of this key" answer.
      if (value.source == fb.ValueSource.valueStatic) return key.defaultValue;
      return key.clamp(value.asInt());
    } catch (_) {
      // A malformed value (a string where an int was expected) throws on
      // asInt(). One bad console entry must not brick the economy.
      return key.defaultValue;
    }
  }

  /// Registers the shipped defaults and fetches, bounded by [fetchTimeout].
  ///
  /// Returns whether the fetch actually landed — bootstrap logs it and moves
  /// on either way. NEVER throws and never blocks past the timeout: this is
  /// step 5 of an init sequence whose steps 5–8 "must never be able to block
  /// or crash startup".
  ///
  /// The defaults are registered BEFORE the fetch, so even a fetch that times
  /// out leaves every key resolvable from the same table [getInt] would fall
  /// back to. Belt and braces: [getInt] does not actually depend on this
  /// having run.
  static Future<bool> activateWithDefaults(
    fb.FirebaseRemoteConfig config, {
    required ErrorReporter reporter,
    Duration timeout = fetchTimeout,
  }) async {
    try {
      await config.setDefaults({
        for (final key in RemoteConfigKeys.all) key.name: key.defaultValue,
      });
      await config.setConfigSettings(
        fb.RemoteConfigSettings(
          fetchTimeout: timeout,
          // Ch14's levers are tuned in hours, not seconds. A short interval
          // would spend a player's data allowance re-asking a question whose
          // answer changes a few times a month.
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      return await config.fetchAndActivate().timeout(timeout);
    } catch (error, stackTrace) {
      // Offline, timed out, or App Check refused the request — all ordinary,
      // all survivable, because every key still resolves to its shipped
      // default. Reported for visibility, never surfaced.
      reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'remoteConfig.fetchAndActivate'},
      );
      return false;
    }
  }
}
