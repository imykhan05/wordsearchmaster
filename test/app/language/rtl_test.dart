import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/language/language_x.dart';
import 'package:word_search_master/app/theme/app_typography.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';
import 'package:word_search_master/domain/text/language.dart';

void main() {
  /// Pumps the app and picks [language] from the FTUE cards, landing on Home.
  ///
  /// The key is per-language on purpose: without it a second `pumpWidget` in
  /// the same test reuses the existing element (and with it the existing
  /// ProviderScope container and router), so the app would still be sitting on
  /// Home rather than back at language select.
  Future<void> pumpAndSelect(WidgetTester tester, Language language) async {
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey('scope-${language.code}'),
        overrides: [appConfigProvider.overrideWithValue(AppConfig.dev())],
        child: const WordSearchMasterApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(language.endonym));
    await tester.pumpAndSettle();
  }

  /// Where the AppBar's title sits horizontally. This is the observable proof
  /// that the layout mirrored, as opposed to merely reporting a direction.
  Rect appBarTitleRect(WidgetTester tester) {
    final title = find
        .descendant(of: find.byType(AppBar), matching: find.byType(Text))
        .first;
    return tester.getRect(title);
  }

  group('Directionality follows the selected language', () {
    testWidgets('Urdu gives the whole subtree RTL', (tester) async {
      await pumpAndSelect(tester, Language.urdu);

      final context = tester.element(find.byType(Scaffold).last);
      expect(Directionality.of(context), TextDirection.rtl);
    });

    testWidgets('Hindi and English give LTR', (tester) async {
      for (final language in [Language.hindi, Language.english]) {
        await pumpAndSelect(tester, language);

        final context = tester.element(find.byType(Scaffold).last);
        expect(
          Directionality.of(context),
          TextDirection.ltr,
          reason: '$language should be LTR',
        );
      }
    });
  });

  group('the UI actually mirrors for Urdu', () {
    testWidgets('AppBar title moves from the left edge to the right', (
      tester,
    ) async {
      await pumpAndSelect(tester, Language.english);
      final ltr = appBarTitleRect(tester);

      await pumpAndSelect(tester, Language.urdu);
      final rtl = appBarTitleRect(tester);

      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      expect(
        ltr.center.dx,
        lessThan(screenWidth / 2),
        reason: 'LTR title should sit in the left half',
      );
      expect(
        rtl.center.dx,
        greaterThan(screenWidth / 2),
        reason: 'RTL title should sit in the right half — the layout mirrored',
      );
      expect(rtl.center.dx, greaterThan(ltr.center.dx));
    });

    testWidgets('padding mirrors: the title is inset from the opposite edge', (
      tester,
    ) async {
      await pumpAndSelect(tester, Language.english);
      final ltr = appBarTitleRect(tester);
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final ltrInsetFromStart = ltr.left;

      await pumpAndSelect(tester, Language.urdu);
      final rtl = appBarTitleRect(tester);
      final rtlInsetFromStart = screenWidth - rtl.right;

      // Directional padding resolved against the reading direction, so the
      // gap from the *start* edge is the same in both.
      expect(rtlInsetFromStart, closeTo(ltrInsetFromStart, 1.0));
    });
  });

  group('locale follows the selected language', () {
    /// The AppBar title, which is a real localized string. The dev route-nav
    /// buttons below it stay English on purpose — they are scaffolding, not
    /// user-facing copy, and the l10n CI check allowlists them.
    String appBarTitle(WidgetTester tester) {
      final title = find
          .descendant(of: find.byType(AppBar), matching: find.byType(Text))
          .first;
      return tester.widget<Text>(title).data!;
    }

    testWidgets('screen titles come back in the selected script', (
      tester,
    ) async {
      await pumpAndSelect(tester, Language.english);
      expect(appBarTitle(tester), 'Home');

      await pumpAndSelect(tester, Language.urdu);
      expect(appBarTitle(tester), 'ہوم');

      await pumpAndSelect(tester, Language.hindi);
      expect(appBarTitle(tester), 'होम');
    });
  });

  group('LanguageX — the Flutter-typed view of a Language', () {
    test('locale matches the ARB suffix', () {
      expect(Language.urdu.locale, const Locale('ur'));
      expect(Language.hindi.locale, const Locale('hi'));
      expect(Language.english.locale, const Locale('en'));
    });

    test('textDirection is RTL for Urdu only', () {
      expect(Language.urdu.textDirection, TextDirection.rtl);
      expect(Language.hindi.textDirection, TextDirection.ltr);
      expect(Language.english.textDirection, TextDirection.ltr);
    });

    test(
      'gridPrimaryDirection is Offset(-1, 0) for Urdu, Offset(1, 0) otherwise',
      () {
        expect(Language.urdu.gridPrimaryDirection, const Offset(-1, 0));
        expect(Language.hindi.gridPrimaryDirection, const Offset(1, 0));
        expect(Language.english.gridPrimaryDirection, const Offset(1, 0));
      },
    );

    test('the Offset view agrees with the pure-Dart vector', () {
      for (final language in Language.values) {
        expect(
          language.gridPrimaryDirection,
          language.primaryDirection.toOffset(),
        );
      }
    });

    test('gridFontFamily is never Nastaliq', () {
      for (final language in Language.values) {
        expect(language.gridFontFamily, isNot(AppFonts.nastaliq));
      }
      expect(Language.urdu.gridFontFamily, AppFonts.naskh);
    });

    test('uiFontFamily is the body-class family — Naskh for Urdu', () {
      expect(Language.urdu.uiFontFamily, AppFonts.naskh);
      expect(Language.hindi.uiFontFamily, AppFonts.devanagari);
      expect(Language.english.uiFontFamily, AppFonts.latin);
    });

    test('GridVector.toOffset preserves the sign convention', () {
      expect(GridVector.south.toOffset(), const Offset(0, 1));
      expect(GridVector.northWest.toOffset(), const Offset(-1, -1));
    });
  });

  group('endonyms', () {
    test('each language names itself in its own script', () {
      expect(Language.urdu.endonym, 'اردو');
      expect(Language.hindi.endonym, 'हिन्दी');
      expect(Language.english.endonym, 'English');
    });

    testWidgets('all three cards are offered on the first screen', (
      tester,
    ) async {
      // A player who reads only Urdu has to be able to find the Urdu card, so
      // the cards are not localized into the currently-active language.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appConfigProvider.overrideWithValue(AppConfig.dev())],
          child: const WordSearchMasterApp(),
        ),
      );
      await tester.pumpAndSettle();

      for (final language in Language.values) {
        expect(find.text(language.endonym), findsOneWidget);
      }
    });
  });
}
