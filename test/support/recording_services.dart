import 'package:word_search_master/services/audio/audio_service.dart';
import 'package:word_search_master/services/haptics/haptics_service.dart';

/// Recording doubles for the two juice services — every call lands in a plain
/// list rather than a mock framework, so a test asserts on a `List<String>`
/// it can print.
///
/// Shared rather than re-declared per file: the click-and-tick pair is now
/// asserted from several places (`tap_feedback_test.dart`,
/// `game_screen_test.dart`), and two copies of a double drift the same way
/// two copies of the code under test do.
final class RecordingAudioService implements AudioService {
  final List<String> allCalls = [];

  /// The combo passed to each [playFound], in order — the pitch ladder is the
  /// one clip whose ARGUMENT matters, not just that it fired.
  final List<int> foundCombos = [];

  /// Every [setMusicPlaying] argument, in order.
  final List<bool> musicPlaying = [];

  @override
  Future<void> preload() async {}

  @override
  Future<void> playFound({required int combo}) async {
    allCalls.add('found:$combo');
    foundCombos.add(combo);
  }

  @override
  Future<void> playWrong() async => allCalls.add('wrong');

  @override
  Future<void> playLevelComplete() async => allCalls.add('levelComplete');

  @override
  Future<void> playDailyComplete() async => allCalls.add('dailyComplete');

  @override
  Future<void> playChestOpen() async => allCalls.add('chestOpen');

  @override
  Future<void> playButtonTap() async => allCalls.add('buttonTap');

  @override
  Future<void> playTransition() async => allCalls.add('transition');

  @override
  Future<void> playShuffle() async => allCalls.add('shuffle');

  @override
  Future<void> playCoin() async => allCalls.add('coin');

  @override
  void setMuted(bool muted) {}

  @override
  Future<void> setMusicPlaying(bool playing) async => musicPlaying.add(playing);
}

final class RecordingHapticsService implements HapticsService {
  final List<String> allCalls = [];

  @override
  void selectionTick() => allCalls.add('selectionTick');

  @override
  void wordFound() => allCalls.add('wordFound');

  @override
  void levelComplete() => allCalls.add('levelComplete');

  @override
  void buttonTap() => allCalls.add('buttonTap');

  @override
  void setEnabled(bool enabled) {}
}
