/// Is there a network right now (Ch10 / P16)?
///
/// An interface plus two bindings, the same shape `AudioService` and
/// `ErrorReporter` already use — because the sync worker has to be drivable
/// from a widget test, and `connectivity_plus` is a platform channel that
/// answers nothing under `flutter_test`.
///
/// ---------------------------------------------------------------------------
/// THIS ANSWERS "IS THERE AN INTERFACE UP", NOT "DOES THE INTERNET WORK"
///
/// `connectivity_plus` reports the state of the radio, so a phone attached to
/// a captive-portal wifi with no route out reports CONNECTED. That is a known
/// limit of every API of this shape, and the design here leans on it rather
/// than fighting it: this signal decides WHEN TO TRY, and the attempt itself
/// decides what actually happened. A false "online" costs one request and a
/// backoff step; a false "offline" would cost a player their sync until the
/// radio state changed again, which on a stable bad connection is never.
///
/// That asymmetry is also why [AssumeOnlineConnectivityService] is the
/// fallback rather than an assume-offline one: every failure mode of guessing
/// "online" is recoverable, and the failure mode of guessing "offline" is a
/// queue that never drains.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_service.g.dart';

abstract interface class ConnectivityService {
  /// The current state, best effort.
  Future<bool> isOnline();

  /// Emits on every CHANGE. Does not replay the current value — callers that
  /// need it ask [isOnline], because a stream that replayed would make "we
  /// just came online, drain the queue" fire on every listener attach.
  Stream<bool> get changes;
}

/// The binding used when the plugin is unavailable or unwired.
///
/// Always online, never changes. See the library header for why this is the
/// safe direction to be wrong in.
final class AssumeOnlineConnectivityService implements ConnectivityService {
  const AssumeOnlineConnectivityService();

  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}

/// The real binding, wired in `bootstrap.dart`.
final class PluginConnectivityService implements ConnectivityService {
  PluginConnectivityService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isOnline() async {
    try {
      return _isOnline(await _connectivity.checkConnectivity());
    } on Object {
      // A platform channel that threw is not evidence of being offline — it is
      // evidence of a broken plugin. Answer the way the header argues for.
      return true;
    }
  }

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged
      .map(_isOnline)
      // The plugin re-emits the same list on unrelated interface changes (a
      // VPN attaching, wifi and mobile swapping while both are up). Without
      // this, every one of those would trigger a full queue scan.
      .distinct();

  /// connectivity_plus returns a LIST, because a device can hold several
  /// interfaces at once. Online means at least one of them is not `none`.
  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}

/// Defaults to the assume-online binding; `bootstrap.dart` overrides it with
/// the plugin-backed one, exactly as it does for `AudioService`.
@Riverpod(keepAlive: true)
ConnectivityService connectivityService(Ref ref) =>
    const AssumeOnlineConnectivityService();

/// Live online/offline, for the indicator and the worker.
///
/// Seeded with a real [ConnectivityService.isOnline] read so the first frame
/// is not a guess, then follows [ConnectivityService.changes].
@Riverpod(keepAlive: true)
Stream<bool> isOnline(Ref ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  yield await service.isOnline();
  yield* service.changes;
}
