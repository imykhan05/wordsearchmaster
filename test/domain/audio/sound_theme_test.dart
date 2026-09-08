import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/audio/sound_theme.dart';

void main() {
  test('every theme has a distinct, non-empty id', () {
    final ids = SoundTheme.values.map((theme) => theme.id).toSet();
    expect(ids, hasLength(SoundTheme.values.length));
    expect(ids.every((id) => id.isNotEmpty), isTrue);
  });

  test('fromId round-trips every value through its own id', () {
    for (final theme in SoundTheme.values) {
      expect(SoundTheme.fromId(theme.id), theme);
    }
  });

  test('fromId falls back to defaultTheme for an unrecognised id', () {
    expect(
      SoundTheme.fromId('a_future_theme_this_build_predates'),
      SoundTheme.defaultTheme,
    );
  });

  test('fromId falls back to defaultTheme for null', () {
    expect(SoundTheme.fromId(null), SoundTheme.defaultTheme);
  });

  test('defaultTheme is softBells', () {
    // Pinned, not just "some member" — it is what a fresh install ships and
    // what a corrupted/unrecognised stored value degrades to.
    expect(SoundTheme.defaultTheme, SoundTheme.softBells);
  });
}
