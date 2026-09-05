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
  final List<bool> musicHistory = [];

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

  @override
  Future<void> setMusicPlaying(bool playing) async {
    calls.add('setMusicPlaying:$playing');
    musicHistory.add(playing);
  }
}

void main() {
  // `musicSyncProvider` builds an `AppLifecycleListener`, which reads
  // `WidgetsBinding.instance` — absent in a plain `test()` until the binding
  // is initialised. Harmless for the rest of the file.
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('musicSyncProvider — the background bed', () {
    ProviderContainer containerWith(
      AudioService fake, {
      bool musicEnabled = true,
    }) {
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(fake),
          uiSettingsStoreProvider.overrideWithValue(
            InMemoryUiSettingsStore(musicEnabled: musicEnabled),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('starts the loop when the setting is already on at startup', () async {
      final fake = _FakeAudioService();
      containerWith(fake).read(musicSyncProvider);
      await Future<void>.delayed(Duration.zero);

      expect(fake.musicHistory, [true]);
    });

    test('a player who turned music OFF never hears it start', () async {
      final fake = _FakeAudioService();
      containerWith(fake, musicEnabled: false).read(musicSyncProvider);
      await Future<void>.delayed(Duration.zero);

      expect(fake.musicHistory, [
        false,
      ], reason: 'the stored preference has to win before the first frame');
    });

    test('toggling the setting drives the loop both ways', () async {
      final fake = _FakeAudioService();
      final container = containerWith(fake, musicEnabled: false);
      container.read(musicSyncProvider);
      await Future<void>.delayed(Duration.zero);

      container.read(musicEnabledProvider.notifier).set(true);
      await Future<void>.delayed(Duration.zero);
      container.read(musicEnabledProvider.notifier).set(false);
      await Future<void>.delayed(Duration.zero);

      expect(fake.musicHistory, [false, true, false]);
    });

    test('music is independent of the SFX mute, not a branch of it', () async {
      // The whole reason `musicEnabled` is its own key: a player muting SFX
      // must not lose the bed, and vice versa.
      final fake = _FakeAudioService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(fake),
          uiSettingsStoreProvider.overrideWithValue(
            InMemoryUiSettingsStore(soundEnabled: true, musicEnabled: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(musicSyncProvider);
      container.read(audioMuteSyncProvider);
      await Future<void>.delayed(Duration.zero);

      container.read(soundEnabledProvider.notifier).set(false);
      await Future<void>.delayed(Duration.zero);

      expect(fake.mutedHistory, [false, true]);
      expect(fake.musicHistory, [
        true,
      ], reason: 'muting the SFX left the music exactly as it was');
    });
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
