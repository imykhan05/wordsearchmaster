import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/app/theme/app_tokens.dart';
import 'package:word_search_master/domain/theme/background_style.dart';
import 'package:word_search_master/presentation/widgets/app_background.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

/// The board background: three token-derived gradients, plus the player's own
/// photo — which is the half that can fail, since it lives in a cache
/// directory the OS may empty whenever it likes.
void main() {
  /// The smallest thing `Image.file` will actually decode: a 1x1 PNG.
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4z8AAAAMBAQDJ/'
    'pfYAAAAAElFTkSuQmCC',
  );

  Future<void> pumpBackground(
    WidgetTester tester, {
    required BackgroundStyle style,
    String? photoPath,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiSettingsStoreProvider.overrideWithValue(
            InMemoryUiSettingsStore(
              backgroundStyle: style,
              backgroundPhotoPath: photoPath,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const AppBackground(child: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
  }

  /// The gradient the layer paints, or null when it is showing something else.
  LinearGradient? paintedGradient(WidgetTester tester) {
    for (final box in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    )) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration &&
          decoration.gradient is LinearGradient) {
        return decoration.gradient! as LinearGradient;
      }
    }
    return null;
  }

  group('gradients', () {
    testWidgets('each style paints its OWN stops, not one shared look', (
      tester,
    ) async {
      final seen = <BackgroundStyle, List<Color>>{};

      for (final style in BackgroundStyle.gradients) {
        await pumpBackground(tester, style: style);
        final gradient = paintedGradient(tester);
        expect(gradient, isNotNull, reason: '${style.id} painted no gradient');
        seen[style] = gradient!.colors;
      }

      // Three swatches that look identical are not a choice.
      final distinct = seen.values.map((colors) => colors.toString()).toSet();
      expect(distinct, hasLength(BackgroundStyle.gradients.length));
    });

    testWidgets('the stops come from the palette, not from literals here', (
      tester,
    ) async {
      await pumpBackground(tester, style: BackgroundStyle.calm);

      final expected = AppTokens
          .darkColors
          .backgroundGradients[BackgroundStyle.calm.gradientIndex];
      expect(paintedGradient(tester)!.colors, [expected.from, expected.to]);
    });

    testWidgets('it runs top to bottom', (tester) async {
      await pumpBackground(tester, style: BackgroundStyle.ember);

      final gradient = paintedGradient(tester)!;
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
    });
  });

  group('photo', () {
    testWidgets('a real file is shown, under a scrim', (tester) async {
      final file = File(
        '${Directory.systemTemp.createTempSync('wsm_bg').path}/pick.png',
      )..writeAsBytesSync(onePixelPng);
      addTearDown(() => file.parent.deleteSync(recursive: true));

      await pumpBackground(
        tester,
        style: BackgroundStyle.photo,
        photoPath: file.path,
      );

      expect(find.byType(Image), findsOneWidget);

      // The scrim is legibility, not decoration: the top bar's score and the
      // word chips are plain text with no card of their own, and a photo can
      // be a white sky.
      final scrim = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((box) => box.color.a == AppBackground.photoScrimOpacity);
      expect(scrim, hasLength(1));
    });

    testWidgets('A MISSING FILE FALLS BACK TO THE GRADIENT, silently', (
      tester,
    ) async {
      // The photo lives in a cache directory Android may empty at any time.
      // The player did nothing wrong, so they get their gradient back and are
      // told nothing — Ch10's rule for a background failure.
      await pumpBackground(
        tester,
        style: BackgroundStyle.photo,
        photoPath: '/does/not/exist/anywhere.png',
      );

      // Resolved at the EDGE, in `BackgroundPhotoPath.build`, so the gradient
      // is on screen from the very first frame — no flash of a broken image
      // while an async load fails, and nothing here depending on when it
      // does.
      expect(find.byType(Image), findsNothing);
      expect(paintedGradient(tester), isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the photo style with no path at all is just the gradient', (
      tester,
    ) async {
      await pumpBackground(tester, style: BackgroundStyle.photo);

      expect(find.byType(Image), findsNothing);
      expect(paintedGradient(tester), isNotNull);
    });
  });
}
