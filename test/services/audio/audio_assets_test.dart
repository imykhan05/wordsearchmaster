import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/services/audio/audio_clip.dart';

/// The audio is no longer GENERATED — `tool/generate_audio_assets.py` synthesized
/// every clip from sine partials and could not produce a missing file. These are
/// real recordings, copied in by hand, so "the enum names a file that is actually
/// there" stopped being true by construction and has to be checked.
///
/// A missing or misnamed file does not crash: `AudioPlayersAudioService.preload`
/// swallows the failure and that clip silently never plays again, which is
/// exactly the kind of bug nobody notices until a player mentions it.
void main() {
  const musicAsset = 'assets/audio/music_loop.mp3';

  test('every AudioClip points at a file that exists and is not empty', () {
    for (final clip in AudioClip.values) {
      final file = File('assets/${clip.assetPath}');
      expect(
        file.existsSync(),
        isTrue,
        reason: '${clip.name} -> ${file.path} is missing',
      );
      expect(
        file.lengthSync(),
        greaterThan(1024),
        reason: '${clip.name} -> ${file.path} is suspiciously small',
      );
    }
  });

  test('the background loop exists', () {
    // Not an AudioClip — it needs ReleaseMode.loop where every SFX needs
    // ReleaseMode.stop, so it is addressed separately by the service and would
    // otherwise be the one audio file nothing checks.
    expect(File(musicAsset).existsSync(), isTrue);
  });

  test('no two clips share a file', () {
    // Two enum values pointing at one file compiles, ships, and reads as "the
    // wrong sound plays" — the shape a copy-paste in the filename map makes.
    final paths = AudioClip.values.map((clip) => clip.assetPath).toList();
    expect(paths.toSet(), hasLength(paths.length));
  });

  test('the shipped set stays inside its size budget', () {
    // CLAUDE.md's standing constraint is a 2GB-RAM phone on an expensive data
    // plan. The three synthesized theme folders this replaced cost ~933KB;
    // going OVER that while shipping one set instead of three would mean the
    // saving argued for in `pubspec.yaml` had quietly stopped being true.
    final total = Directory('assets/audio')
        .listSync()
        .whereType<File>()
        .fold<int>(0, (sum, file) => sum + file.lengthSync());
    expect(
      total,
      lessThan(933 * 1024),
      reason: 'assets/audio is ${(total / 1024).round()}KB',
    );
  });

  test('every file in the folder is claimed by something', () {
    // The other direction: an orphan left behind by a rename ships in the APK
    // and is never played.
    final claimed = {
      for (final clip in AudioClip.values) 'assets/${clip.assetPath}',
      musicAsset,
    };
    final onDisk = Directory('assets/audio')
        .listSync()
        .whereType<File>()
        .map((file) => file.path)
        .toSet();
    expect(onDisk.difference(claimed), isEmpty);
  });
}
