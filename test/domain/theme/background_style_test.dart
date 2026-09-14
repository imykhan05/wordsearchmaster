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

  test('defaultStyle is brandArt — the bundled artwork ships as the first '
      'thing a new install sees', () {
    // PLAYER-REQUESTED: a considered background from the first launch,
    // rather than the flat gradient every earlier build defaulted to. A
    // player who prefers a plain colour, or their own photo, still reaches
    // either in one tap from Settings — this only changes what a player who
    // never opens Settings sees.
    expect(BackgroundStyle.defaultStyle, BackgroundStyle.brandArt);
  });

  test('gradients offers only the plain-colour swatches — not photo, not '
      'brandArt', () {
    // The picker shows the three colour swatches, the bundled-art chip, and
    // one file-chooser action, each rendered by its own bit of UI in
    // `settings_screen.dart` — neither `brandArt` nor `photo` paints a
    // `DecoratedBox` gradient, so a caller that means "the flat swatches"
    // needs both excluded, not just the one that opens a file picker.
    expect(BackgroundStyle.gradients, isNot(contains(BackgroundStyle.photo)));
    expect(
      BackgroundStyle.gradients,
      isNot(contains(BackgroundStyle.brandArt)),
    );
    expect(
      BackgroundStyle.gradients,
      hasLength(BackgroundStyle.values.length - 2),
    );
  });

  test(
    'every style names a real gradient slot, photo and brandArt included',
    () {
      // `photo` and `brandArt`'s indices are their FALLBACK: a picked photo
      // lives in a cache directory the OS may empty at any time, and the
      // bundled asset could in principle fail to decode — neither has to mean
      // a blank screen.
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
        BackgroundStyle.calm.gradientIndex,
      );
      expect(
        BackgroundStyle.brandArt.gradientIndex,
        BackgroundStyle.calm.gradientIndex,
      );
    },
  );
}
