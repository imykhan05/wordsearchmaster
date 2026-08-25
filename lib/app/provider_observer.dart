import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Logs provider failures to the console. Attached only for [Flavor.dev] —
/// see `_observersFor` in `app.dart`.
final class AppProviderObserver extends ProviderObserver {
  const AppProviderObserver();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      '[provider error] ${context.provider.name ?? context.provider.runtimeType}: $error',
    );
  }
}
