import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
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

  /// A traced run that matched nothing — see [AudioClip.wrong] for why this
  /// exists at all, given Ch03 originally specified silence here.
  Future<void> playWrong();

  Future<void> playLevelComplete();

  /// The Daily Challenge's own finish, distinct from an ordinary level's.
  Future<void> playDailyComplete();

  Future<void> playChestOpen();

  Future<void> playButtonTap();

  /// Advancing to the next level from the level-complete card.
  Future<void> playTransition();

  /// The 180° board flip.
  Future<void> playShuffle();

  Future<void> playCoin();

  /// Gates every future `play*` call AND stops whatever is audible right
  /// now — "master mute respected instantly, mid-playback" (Ch03) rules out
  /// a mute that only takes effect on the NEXT sound.
  void setMuted(bool muted);

  /// Starts or stops the looping background bed.
  ///
  /// Independent of [setMuted], which is the SFX toggle: the two are separate
  /// switches in the UI because players want them separately (see
  /// `UiSettingsStore.musicEnabled`). Idempotent in both directions — the
  /// sync provider calls it on every settings change and on every app
  /// lifecycle transition, so "already playing" and "already stopped" both
  /// have to be no-ops rather than restarts.
  Future<void> setMusicPlaying(bool playing);
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
  Future<void> playWrong() async {}

  @override
  Future<void> playLevelComplete() async {}

  @override
  Future<void> playDailyComplete() async {}

  @override
  Future<void> playChestOpen() async {}

  @override
  Future<void> playButtonTap() async {}

  @override
  Future<void> playTransition() async {}

  @override
  Future<void> playShuffle() async {}

  @override
  Future<void> playCoin() async {}

  @override
  void setMuted(bool muted) {}

  @override
  Future<void> setMusicPlaying(bool playing) async {}
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

  /// The looping background bed. Deliberately NOT an [AudioClip] in the
  /// pooled set: it needs [ReleaseMode.loop] where every SFX needs
  /// [ReleaseMode.stop], it plays for the whole session where they last
  /// ~100ms, and `preload` would otherwise build three players for it.
  ///
  /// The file is a 32-second segment cut from the supplied track with its
  /// tail cross-faded onto its head, so the wrap is continuous rather than a
  /// click. Measured at build time against the same bar the old generated
  /// loop used: the sample step ACROSS the wrap is 5, where the largest step
  /// already inside the track is 1353 — a ratio of 0.004, so the seam is far
  /// below any transient the music itself contains.
  static const String _musicAsset = 'audio/music_loop.mp3';

  /// Well under the SFX. The bed exists to be noticed only when it stops.
  static const double _musicVolume = 0.35;

  /// The context every player is created with — see [preload]'s header for
  /// the whole argument. Named and exposed rather than written inline at the
  /// one call site so a test can assert the focus mode directly: the failure
  /// this guards against is someone restoring the plugin's own default
  /// (`AndroidAudioFocus.gain`) while tidying, which produces no error, no
  /// warning and no failing test anywhere else — only silent background
  /// music on a real device, which is how it reached a player the first time.
  ///
  /// Not `const`: `AudioContext`'s constructor validates in a body, so it is
  /// not a const constructor even though every argument here is one.
  @visibleForTesting
  static AudioContext get focusFreeContext => AudioContext(
    android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
  );

  final Map<AudioClip, List<AudioPlayer>> _pools = {};
  final Map<AudioClip, int> _nextPlayerIndex = {};
  AudioPlayer? _music;
  bool _musicPlaying = false;
  StreamSubscription<PlayerState>? _musicWatchdog;
  bool _muted = false;

  /// EVERY PLAYER THIS APP CREATES REQUESTS NO ANDROID AUDIO FOCUS, and that
  /// one line is what keeps the background bed alive for a whole session.
  ///
  /// `audioplayers` defaults each player to `AUDIOFOCUS_GAIN`
  /// (`AudioContextAndroid`'s own default), requested on every `resume`.
  /// Android grants it to the newest requester and sends `AUDIOFOCUS_LOSS` to
  /// the previous holder — which, inside one app, means OUR OWN SFX evicting
  /// OUR OWN MUSIC. `WrappedPlayer`'s loss handler treats a non-transient
  /// loss as final (`pause()`, clearing its `playing` flag), so the bed did
  /// not merely duck: the very first button tap or found-word chime killed it
  /// permanently, and nothing in this app ever calls `setMusicPlaying` again
  /// to bring it back. The reported symptom was exactly that shape — music at
  /// launch, silence from the first tap onward, which reads as "the music
  /// stops when the game starts".
  ///
  /// Set to [AndroidAudioFocus.none] for the bed as well as the SFX, not just
  /// for the SFX, which would also have fixed the eviction. Three reasons:
  ///
  /// 1. With no player anywhere in the app requesting focus, no player can
  ///    ever be told to lose it. That makes the bug impossible rather than
  ///    avoided, which is the standard the rest of this codebase holds itself
  ///    to (Ch10's "a property, not a promise").
  /// 2. `pause` does not abandon focus — only `stop` does, and
  ///    [setMusicPlaying] deliberately pauses so the loop resumes mid-bar. A
  ///    bed holding `GAIN` would therefore keep another app's music silenced
  ///    for as long as ours sat in the background.
  /// 3. It is the polite answer for this audience. Ch01's player is on a 2GB
  ///    phone, often with their own music or a radio stream already playing;
  ///    a relaxed offline puzzle has no business interrupting it. The player
  ///    already owns that decision through the Music switch in Settings —
  ///    turn it off and only the SFX play, over whatever they had on.
  ///
  /// This is a GLOBAL default rather than a per-player call because the
  /// Android plugin hands each newly created player a copy of the global
  /// context at construction time, so setting it once here — before the first
  /// `AudioPlayer(...)` below — covers all 28 of them with no ordering trap.
  /// Nothing else about the context moves: `contentType`/`usageType` keep
  /// their `music`/`media` defaults, since only focus is implicated.
  @override
  Future<void> preload() async {
    await AudioPlayer.global.setAudioContext(focusFreeContext);

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

    final music = AudioPlayer(playerId: 'music_loop');
    await music.setReleaseMode(ReleaseMode.loop);
    await music.setVolume(_musicVolume);
    await music.setSource(AssetSource(_musicAsset));
    _music = music;

    // Honour an intent recorded before there was a player to carry it.
    // [setMusicPlaying] returns early when `_music` is null, keeping only the
    // flag; without this line that flag then sat true forever while the bed
    // never started, because the next call sees `playing == _musicPlaying`
    // and returns early too. `bootstrap.dart` awaits this preload before
    // `runApp`, so today `musicSync` always fires after it — but that is an
    // ordering nothing here enforces, and the failure it would produce is
    // silent.
    if (_musicPlaying) {
      try {
        await music.resume();
      } catch (_) {
        // Same rule as everywhere else in this file: juice never surfaces.
      }
    }

    // SELF-HEALING WATCHDOG. Everything above stops OUR OWN code from ever
    // pausing the bed for a reason the player did not ask for — but a real
    // device answers to more than our own code. Some OEM battery/audio
    // managers (aggressively so on several popular Android skins) pause a
    // background `MediaPlayer` on their own initiative — a screen-off timer,
    // a "smart" power-save mode, a doze-adjacent heuristic — through a path
    // that never touches the public `AudioFocus` API this class already
    // eliminated every request against. There is no API to opt out of that
    // behaviour; the only thing to do is notice it happened and undo it.
    //
    // So the music player's own state stream is watched for the rest of the
    // session: any time it lands on `paused` or `stopped` while [_musicPlaying]
    // still says it SHOULD be playing, resume it immediately. The ordering
    // that makes this safe is [setMusicPlaying] itself — it flips
    // [_musicPlaying] to `false` BEFORE calling `pause()`, so an intentional
    // pause (the Music toggle, the app backgrounding) is already reflected
    // here by the time the state change arrives, and this listener sees
    // nothing to correct. Only a pause NEITHER of those two paths asked for
    // gets fought.
    _musicWatchdog = music.onPlayerStateChanged.listen((state) {
      if (_musicPlaying &&
          (state == PlayerState.paused || state == PlayerState.stopped)) {
        unawaited(music.resume());
      }
    });
  }

  /// Whether the watchdog above is armed. Exists for
  /// `audio_service_test.dart` to prove [preload] actually wires it up —
  /// nothing else in this class ever reads [_musicWatchdog] itself, since it
  /// lives for the rest of the process and there is no dispose path for a
  /// `keepAlive` singleton to cancel it from.
  @visibleForTesting
  bool get hasMusicWatchdog => _musicWatchdog != null;

  @override
  Future<void> playFound({required int combo}) {
    return _playPooled(
      AudioClip.found,
      rate: ComboPitchLadder.rateForCombo(combo),
    );
  }

  @override
  Future<void> playWrong() => _playPooled(AudioClip.wrong);

  @override
  Future<void> playLevelComplete() => _playPooled(AudioClip.levelComplete);

  @override
  Future<void> playDailyComplete() => _playPooled(AudioClip.dailyComplete);

  @override
  Future<void> playChestOpen() => _playPooled(AudioClip.chestOpen);

  @override
  Future<void> playButtonTap() => _playPooled(AudioClip.buttonTap);

  @override
  Future<void> playTransition() => _playPooled(AudioClip.transition);

  @override
  Future<void> playShuffle() => _playPooled(AudioClip.shuffle);

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
  Future<void> setMusicPlaying(bool playing) async {
    final music = _music;
    // Before `preload`, or after it failed: remember the intent so the state
    // is right, but there is nothing to drive yet.
    if (music == null) {
      _musicPlaying = playing;
      return;
    }
    if (playing == _musicPlaying) return;
    _musicPlaying = playing;
    try {
      // `pause` rather than `stop`: the player keeps its position, so
      // returning from a phone call resumes the bed where it was instead of
      // restarting the loop from the top.
      await (playing ? music.resume() : music.pause());
    } catch (_) {
      // Same rule as the SFX below: audio is juice, and juice never
      // surfaces an error to the player (CLAUDE.md → Never do).
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

/// Keeps the background loop in step with BOTH the music toggle and the app's
/// own lifecycle.
///
/// The lifecycle half is not optional politeness: without it the bed keeps
/// playing over whatever the player switched to — a call, a video, another
/// game — which is the fastest way to get an app muted at the OS level for
/// good. [AppLifecycleListener] gives the two transitions that matter, and
/// `setMusicPlaying` is idempotent so the overlapping sources of truth here
/// (a toggle change while backgrounded, say) cannot double-start it.
///
/// Watched once, at the app root, next to [audioMuteSync].
@Riverpod(keepAlive: true)
void musicSync(Ref ref) {
  var enabled = false;
  var foreground = true;

  void apply() {
    unawaited(
      ref.read(audioServiceProvider).setMusicPlaying(enabled && foreground),
    );
  }

  final lifecycle = AppLifecycleListener(
    onHide: () {
      foreground = false;
      apply();
    },
    onShow: () {
      foreground = true;
      apply();
    },
  );
  ref.onDispose(lifecycle.dispose);

  ref.listen<bool>(musicEnabledProvider, (previous, value) {
    enabled = value;
    apply();
  }, fireImmediately: true);
}
