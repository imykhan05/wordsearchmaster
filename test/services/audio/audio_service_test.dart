import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/services/audio/audio_service.dart';
import 'package:word_search_master/services/audio/sound_settings.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

/// A recording double, not a mock framework: every call this test cares
/// about lands in a plain list it can assert on directly.
final class _FakeAudioService implements AudioService {
  final List<String> calls = [];
  final List<bool> mutedHistory = [];

  @override
  Future<void> preload() async => calls.add('preload');

  @override
  Future<void> playFound({required int combo}) async =>
      calls.add('found:$combo');

  @override
  Future<void> playLevelComplete() async => calls.add('levelComplete');

  @override
  Future<void> playChestOpen() async => calls.add('chestOpen');

  @override
  Future<void> playButtonTap() async => calls.add('buttonTap');

  @override
  Future<void> playCoin() async => calls.add('coin');

  @override
  void setMuted(bool muted) {
    calls.add('setMuted:$muted');
    mutedHistory.add(muted);
  }
}

void main() {
  group('NoopAudioService', () {
    test(
      'every call is a harmless no-op — the pre-bootstrap-override binding',
      () async {
        const service = NoopAudioService();
        await service.preload();
        await service.playFound(combo: 4);
        await service.playLevelComplete();
        await service.playChestOpen();
        await service.playButtonTap();
        await service.playCoin();
        service.setMuted(true);
        // Reaching here without throwing IS the assertion.
      },
    );
  });

  group('audioMuteSyncProvider', () {
    ProviderContainer containerWith(
      AudioService fake, {
      bool soundEnabled = true,
    }) {
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(fake),
          uiSettingsStoreProvider.overrideWithValue(
            InMemoryUiSettingsStore(soundEnabled: soundEnabled),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('syncs the CURRENT sound setting the instant it is read — fireImmediately', () {
      final fake = _FakeAudioService();
      final container = containerWith(fake, soundEnabled: false);

      container.read(audioMuteSyncProvider);

      expect(
        fake.mutedHistory,
        [true],
        reason: 'sound already off at startup must mute before any sound plays',
      );
    });

    test('sound already on at startup never mutes', () {
      final fake = _FakeAudioService();
      final container = containerWith(fake, soundEnabled: true);

      container.read(audioMuteSyncProvider);

      expect(fake.mutedHistory, [false]);
    });

    test('toggling the sound setting mutes/unmutes instantly, mid-session', () {
      final fake = _FakeAudioService();
      final container = containerWith(fake, soundEnabled: true);
      container.read(audioMuteSyncProvider);

      container.read(soundEnabledProvider.notifier).set(false);
      expect(fake.mutedHistory, [false, true]);

      container.read(soundEnabledProvider.notifier).set(true);
      expect(fake.mutedHistory, [false, true, false]);
    });
  });
}
