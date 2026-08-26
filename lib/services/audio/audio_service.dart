import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'audio_clip.dart';
import 'combo_pitch_ladder.dart';
import 'sound_settings.dart';

part 'audio_service.g.dart';

/// The Ch03 SFX layer: `found`'s combo pitch ladder plus the four static
/// clips. Behind an interface for the same reason `ErrorReporter` and
/// `AdGateway` are (CLAUDE.md → Architecture): nothing outside `services/`
/// may import an audio backend directly, and tests need a service they can
/// assert on rather than a real player.
abstract interface class AudioService {
  /// Loads every clip in [AudioClip.values] into memory. Call once, before
  /// the first frame that could trigger a sound — "first-play latency must
  /// be imperceptible" (Ch03) means the fetch/decode cost has to be paid
  /// here, never on the first `playFound`.
  Future<void> preload();

  /// The combo pitch ladder. [combo] is the 1-based streak length exactly as
  /// `GameState.combo` reports it; [ComboPitchLadder.rateForCombo] turns it
  /// into the playback-rate multiplier.
  Future<void> playFound({required int combo});

  Future<void> playLevelComplete();

  /// Not wired to any UI yet (the chest/reward screen is P15/P16 territory),
  /// but the service exposes it now so those prompts only ever call this
  /// method and never touch the audio layer itself.
  Future<void> playChestOpen();

  Future<void> playButtonTap();

  Future<void> playCoin();

  /// Gates every future `play*` call AND stops whatever is audible right
  /// now — "master mute respected instantly, mid-playback" (Ch03) rules out
  /// a mute that only takes effect on the NEXT sound.
  void setMuted(bool muted);
}

/// Drops every call on the floor. The binding for tests and for anything
/// that runs before `bootstrap.dart`'s real-service override lands.
final class NoopAudioService implements AudioService {
  const NoopAudioService();

  @override
  Future<void> preload() async {}

  @override
  Future<void> playFound({required int combo}) async {}

  @override
  Future<void> playLevelComplete() async {}

  @override
  Future<void> playChestOpen() async {}

  @override
  Future<void> playButtonTap() async {}

  @override
  Future<void> playCoin() async {}

  @override
  void setMuted(bool muted) {}
}

/// Real playback via `package:audioplayers`.
///
/// Each [AudioClip] gets its own small ROTATING POOL of [AudioPlayer]s
/// rather than one shared player, so a fast player finding two words in
/// quick succession doesn't cut the first "found" sound off to start the
/// second — the pool absorbs the overlap instead. [_playersPerClip] players
/// per clip is comfortably more than a human can trigger inside one clip's
/// ~100ms lifetime.
///
/// Every player is preloaded via [AudioPlayer.setSource] up front and kept
/// at [ReleaseMode.stop] (never the default `release`), which is what makes
/// a play call cheap: `setSource` pays the asset-decode cost exactly once
/// per player in [preload], and `stop` — unlike `release` — keeps the
/// decoded source resident, so every later play only needs a playback-rate
/// change plus a resume, never a re-fetch.
///
/// Deliberately NOT `PlayerMode.lowLatency`: that mode stops firing the
/// completion/state events the rare-overlap guard in [_playPooled] depends
/// on, and disables [AudioPlayer.seek] outright. The default `mediaPlayer`
/// mode's extra platform-channel overhead is the trade for keeping both of
/// those correct.
final class AudioPlayersAudioService implements AudioService {
  static const int _playersPerClip = 3;

  final Map<AudioClip, List<AudioPlayer>> _pools = {};
  final Map<AudioClip, int> _nextPlayerIndex = {};
  bool _muted = false;

  @override
  Future<void> preload() async {
    for (final clip in AudioClip.values) {
      final pool = <AudioPlayer>[];
      for (var i = 0; i < _playersPerClip; i++) {
        final player = AudioPlayer(playerId: 'sfx_${clip.name}_$i');
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(clip.assetPath));
        pool.add(player);
      }
      _pools[clip] = pool;
      _nextPlayerIndex[clip] = 0;
    }
  }

  @override
  Future<void> playFound({required int combo}) {
    return _playPooled(
      AudioClip.found,
      rate: ComboPitchLadder.rateForCombo(combo),
    );
  }

  @override
  Future<void> playLevelComplete() => _playPooled(AudioClip.levelComplete);

  @override
  Future<void> playChestOpen() => _playPooled(AudioClip.chestOpen);

  @override
  Future<void> playButtonTap() => _playPooled(AudioClip.buttonTap);

  @override
  Future<void> playCoin() => _playPooled(AudioClip.coin);

  Future<void> _playPooled(AudioClip clip, {double rate = 1.0}) async {
    if (_muted) return;
    final pool = _pools[clip];
    if (pool == null || pool.isEmpty) return;
    final index = _nextPlayerIndex[clip]!;
    _nextPlayerIndex[clip] = (index + 1) % pool.length;
    final player = pool[index];
    try {
      // Only the rare same-slot overlap needs an explicit rewind — the
      // common case is already stopped/completed, and resume() on those
      // restarts from position zero on its own.
      if (player.state == PlayerState.playing) {
        await player.seek(Duration.zero);
      }
      await player.setPlaybackRate(rate);
      await player.resume();
    } catch (_) {
      // Best-effort juice: a failed SFX must never crash or surface to the
      // player (CLAUDE.md → Never do).
    }
  }

  @override
  void setMuted(bool muted) {
    _muted = muted;
    if (!muted) return;
    for (final pool in _pools.values) {
      for (final player in pool) {
        // Fire-and-forget: the mute itself is the `_muted` flag above,
        // already in effect for every future play call; stopping whatever
        // is CURRENTLY audible is a best-effort cleanup that must not make
        // callers of this synchronous method await a platform round trip.
        unawaited(player.stop());
      }
    }
  }
}

/// The app-wide service. `bootstrap.dart` overrides this with
/// [AudioPlayersAudioService] once its preload step has run; every other
/// binding (tests, and any code that runs before that override lands) gets
/// [NoopAudioService].
@Riverpod(keepAlive: true)
AudioService audioService(Ref ref) => const NoopAudioService();

/// Keeps [AudioService.setMuted] in sync with the player's sound toggle.
///
/// A `ref.listen` inside a provider body, not a direct `setMuted` call next
/// to the `ref.watch` — Riverpod's own rule is that a build method computes
/// a value and stays free of side effects, and `listen` is the documented
/// escape hatch for exactly this "run an imperative call when another
/// provider changes" shape. `fireImmediately: true` also syncs the state
/// the persisted toggle already had at startup, not only future changes.
///
/// Watched once, at the app root (`app.dart`) — there is no per-screen
/// reason to watch it more than once.
@Riverpod(keepAlive: true)
void audioMuteSync(Ref ref) {
  ref.listen<bool>(soundEnabledProvider, (previous, enabled) {
    ref.read(audioServiceProvider).setMuted(!enabled);
  }, fireImmediately: true);
}
