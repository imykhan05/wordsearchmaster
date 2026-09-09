import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/theme/background_style.dart';

void main() {
  test('every style has a distinct, non-empty id', () {
    final ids = BackgroundStyle.values.map((style) => style.id).toSet();
    expect(ids, hasLength(BackgroundStyle.values.length));
    expect(ids.every((id) => id.isNotEmpty), isTrue);
  });

  test('fromId round-trips every value through its own id', () {
    for (final style in BackgroundStyle.values) {
      expect(BackgroundStyle.fromId(style.id), style);
    }
  });

  test('fromId falls back to the default for an unrecognised id, and null', () {
    // A downgrade, or a style retired in a later release. Neither is an error
    // a player should ever be shown.
    expect(
      BackgroundStyle.fromId('a_style_this_build_predates'),
      BackgroundStyle.defaultStyle,
    );
    expect(BackgroundStyle.fromId(null), BackgroundStyle.defaultStyle);
  });

  test('defaultStyle is calm — the closest thing to the flat ground the app '
      'shipped with', () {
    // Pinned: an existing player's screen must not change under them on an
    // upgrade that only ADDED the ability to change it.
    expect(BackgroundStyle.defaultStyle, BackgroundStyle.calm);
  });

  test('gradients offers every style EXCEPT photo', () {
    // The picker shows swatches plus one file-chooser action; a photo is not
    // a swatch, and offering it as one would show an empty chip to a player
    // who has never picked an image.
    expect(BackgroundStyle.gradients, isNot(contains(BackgroundStyle.photo)));
    expect(
      BackgroundStyle.gradients,
      hasLength(BackgroundStyle.values.length - 1),
    );
  });

  test('every style names a real gradient slot, photo included', () {
    // `photo`'s index is its FALLBACK: the file lives in a cache directory the
    // OS may empty at any time, so the style has to have somewhere to land
    // that is not a blank screen.
    for (final style in BackgroundStyle.values) {
      expect(style.gradientIndex, greaterThanOrEqualTo(0));
      expect(
        style.gradientIndex,
        lessThan(BackgroundStyle.gradients.length),
        reason: '${style.id} points past the end of the gradient list',
      );
    }
    expect(
      BackgroundStyle.photo.gradientIndex,
      BackgroundStyle.defaultStyle.gradientIndex,
    );
  });
}
