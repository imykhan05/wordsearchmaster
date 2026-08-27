import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/router.dart';
import 'package:word_search_master/domain/text/language.dart';

import '../support/fake_meta.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, AppConfig config) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          ...fakeMetaOverrides(),
        ],
        child: const WordSearchMasterApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The FTUE opens on language select, so anything past it is only reachable
  /// after picking a language.
  Future<void> enterApp(WidgetTester tester, AppConfig config) async {
    await pumpApp(tester, config);
    await tester.tap(find.text(Language.english.endonym));
    await tester.pumpAndSettle();
  }

  /// Navigates by ROUTE rather than by tapping a nav button.
  ///
  /// P11 replaced the home screen's `StubScreen` — and with it the dev
  /// route-nav row that used to carry a "Style Gallery" button — with the real
  /// Ch02 home. Driving the router directly is what this test always meant
  /// anyway: the claim under test is "the gallery route is registered on dev
  /// and renders", not "some other screen links to it".
  Future<void> openGallery(WidgetTester tester) async {
    await enterApp(tester, AppConfig.dev());

    final context = tester.element(find.byType(Navigator).first);
    GoRouter.of(context).go(const StyleGalleryRoute().location);
    await tester.pumpAndSettle();
  }

  /// The gallery is a lazy [ListView], so a section below the fold is not
  /// built until scrolled to.
  Future<void> scrollTo(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Route table inspection, in a plain `test` rather than `testWidgets`:
  /// reading a provider off a bare container schedules Riverpod's dispose
  /// timer, which trips the widget binding's "no pending timers" invariant.
  Iterable<String> registeredRoutes(AppConfig config) {
    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWithValue(config)],
    );
    addTearDown(container.dispose);
    return container
        .read(routerProvider)
        .configuration
        .routes
        .whereType<GoRoute>()
        .map((route) => route.path);
  }

  group('dev flavor', () {
    testWidgets('gallery opens and shows every token section', (tester) async {
      await openGallery(tester);

      expect(find.text('Scripts'), findsOneWidget);

      for (final section in const [
        'Type scale',
        'Colours — both themes',
        'Found-word highlights',
        'Spacing',
        'Radii',
        'Elevation',
        'Motion',
      ]) {
        await scrollTo(tester, section);
        expect(find.text(section), findsOneWidget, reason: '$section section');
      }
    });

    testWidgets('renders all three scripts, with correct grapheme splitting', (
      tester,
    ) async {
      await openGallery(tester);

      // Urdu: connected word chip, plus the isolated letters a grid shows.
      expect(find.text('پانی'), findsOneWidget);
      expect(find.text('پ'), findsOneWidget);

      // Hindi: "पानी" is TWO cells (पा, नी), not four code points — Ch04's
      // grapheme rule, visible right here rather than only in a unit test.
      expect(find.text('पानी'), findsOneWidget);
      expect(find.text('पा'), findsOneWidget);
      expect(find.text('नी'), findsOneWidget);
      expect(
        find.text('ा'),
        findsNothing,
        reason: 'a bare matra in its own cell means code-point splitting',
      );

      expect(find.text('WATER'), findsOneWidget);
    });

    testWidgets('theme toggle switches brightness', (tester) async {
      await openGallery(tester);

      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.light_mode_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    });

    test('router registers the gallery route', () {
      expect(
        registeredRoutes(AppConfig.dev()),
        contains(const StyleGalleryRoute().location),
      );
    });
  });

  for (final config in [AppConfig.stg(), AppConfig.prod()]) {
    final flavor = config.flavor.name;

    group('$flavor flavor', () {
      testWidgets('offers no way into the gallery', (tester) async {
        await enterApp(tester, config);
        expect(
          find.widgetWithText(OutlinedButton, 'Style Gallery'),
          findsNothing,
        );
      });

      test('does not register the gallery route at all', () {
        // Not merely hidden: the route is absent from the table, so a deep
        // link cannot reach it either.
        expect(
          registeredRoutes(config),
          isNot(contains(const StyleGalleryRoute().location)),
        );
      });
    });
  }
}
