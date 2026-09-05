import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/application/notification_sync.dart';
import 'package:word_search_master/data/remote/notification_registration_api.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/auth/auth_service.dart';
import 'package:word_search_master/services/notifications/notification_service.dart';
import 'package:word_search_master/services/notifications/notification_settings.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

/// `notificationRegistrationSync` keeps `users/{uid}.fcmToken`/`language`
/// current (post-P17). These tests exercise the one thing added on top of
/// that for the in-app opt-out: with [StreakRemindersEnabled] off, the
/// record must still go out — `language` has to stay current either way —
/// just with a null `fcmToken`, reusing `sendDueStreakReminders`' own
/// existing "no token, no push" guard rather than a second server-side flag.
void main() {
  ProviderContainer harness({
    required AuthService auth,
    NotificationService? notifications,
    UiSettingsStore? settings,
  }) {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        notificationServiceProvider.overrideWithValue(
          notifications ?? const _FakeNotificationService('token-1'),
        ),
        notificationRegistrationApiProvider.overrideWithValue(
          _RecordingNotificationRegistrationApi(),
        ),
        uiSettingsStoreProvider.overrideWithValue(
          settings ??
              InMemoryUiSettingsStore(selectedLanguage: Language.english),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  _RecordingNotificationRegistrationApi apiOf(ProviderContainer container) =>
      container.read(notificationRegistrationApiProvider)
          as _RecordingNotificationRegistrationApi;

  test(
    'registers the real token when reminders are enabled (the default)',
    () async {
      final container = harness(
        auth: const _FakeAuth(AuthAccount(uid: 'u1', isAnonymous: true)),
      );

      container.listen(notificationRegistrationSyncProvider, (_, _) {});
      await pumpEventQueue();

      final calls = apiOf(container).calls;
      expect(calls, hasLength(1));
      expect(calls.single.fcmToken, 'token-1');
      expect(calls.single.language, 'en');
    },
  );

  test('registers a NULL token when reminders are disabled, language stays current', () async {
    final settings = InMemoryUiSettingsStore(
      selectedLanguage: Language.english,
      streakRemindersEnabled: false,
    );
    final container = harness(
      auth: const _FakeAuth(AuthAccount(uid: 'u1', isAnonymous: true)),
      settings: settings,
    );

    container.listen(notificationRegistrationSyncProvider, (_, _) {});
    await pumpEventQueue();

    final calls = apiOf(container).calls;
    expect(calls, hasLength(1));
    expect(calls.single.fcmToken, isNull);
    expect(calls.single.language, 'en');
  });

  test('flipping the toggle off re-registers with a null token', () async {
    final settings = InMemoryUiSettingsStore(
      selectedLanguage: Language.english,
    );
    final container = harness(
      auth: const _FakeAuth(AuthAccount(uid: 'u1', isAnonymous: true)),
      settings: settings,
    );
    container.listen(notificationRegistrationSyncProvider, (_, _) {});
    await pumpEventQueue();
    expect(apiOf(container).calls.last.fcmToken, 'token-1');

    container.read(streakRemindersEnabledProvider.notifier).set(false);
    await pumpEventQueue();

    expect(apiOf(container).calls.last.fcmToken, isNull);
  });

  test(
    'flipping the toggle back on re-registers with the real token',
    () async {
      final settings = InMemoryUiSettingsStore(
        selectedLanguage: Language.english,
        streakRemindersEnabled: false,
      );
      final container = harness(
        auth: const _FakeAuth(AuthAccount(uid: 'u1', isAnonymous: true)),
        settings: settings,
      );
      container.listen(notificationRegistrationSyncProvider, (_, _) {});
      await pumpEventQueue();
      expect(apiOf(container).calls.last.fcmToken, isNull);

      container.read(streakRemindersEnabledProvider.notifier).set(true);
      await pumpEventQueue();

      expect(apiOf(container).calls.last.fcmToken, 'token-1');
    },
  );

  test('no signed-in account means no registration call at all', () async {
    final container = harness(auth: const _FakeAuth(null));

    container.listen(notificationRegistrationSyncProvider, (_, _) {});
    await pumpEventQueue();

    expect(apiOf(container).calls, isEmpty);
  });
}

final class _FakeAuth implements AuthService {
  const _FakeAuth(this._account);

  final AuthAccount? _account;

  @override
  AuthAccount? get currentAccount => _account;

  @override
  Stream<AuthAccount?> watchAccount() =>
      _account == null ? const Stream.empty() : Stream.value(_account);

  @override
  Future<AuthAccount?> ensureSignedIn() async => _account;

  @override
  Future<LinkOutcome> linkWithGoogle() async => const LinkCancelled();

  @override
  String? get lastGoogleSignInDiagnostic => null;

  @override
  Future<AuthAccount?> signOut() async => _account;
}

final class _FakeNotificationService implements NotificationService {
  const _FakeNotificationService(this._token);

  final String? _token;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String?> getToken() async => _token;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}

typedef _RegisterCall = ({String uid, String? fcmToken, String language});

final class _RecordingNotificationRegistrationApi
    implements NotificationRegistrationApi {
  final List<_RegisterCall> calls = [];

  @override
  Future<void> register({
    required String uid,
    required String? fcmToken,
    required String language,
  }) async {
    calls.add((uid: uid, fcmToken: fcmToken, language: language));
  }
}
