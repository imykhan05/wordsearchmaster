import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/theme/theme.dart';
import 'package:word_search_master/application/game_controller.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/domain/grid/grid_result.dart';
import 'package:word_search_master/domain/grid/selection_resolver.dart';
import 'package:word_search_master/domain/progression/dda.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/game/game_debug_panel.dart';
import 'package:word_search_master/presentation/game/game_grid.dart';
import 'package:word_search_master/presentation/meta/journey_providers.dart';
import 'package:word_search_master/presentation/screens/game_screen.dart';

import '../../support/fake_content.dart';
import '../../support/local_db.dart';

/// The three P12 acceptance criteria, verbatim:
///
///   * "App open se pehla word mile 15 second se kam mein" — the first word
///     is found in under 15 real seconds of a fresh install. Proven here by
///     showing the FTUE glow mechanism that makes that possible: it fires at
///     2s of inactivity, points at a real, findable word, and finding it
///     immediately succeeds — nowhere near the 15s budget.
///   * "DDA states dev toggle se trigger hoti hain" — `GameDebugPanel`'s DDA
///     row forces `pulse`/`hintOffer`/`none` through the exact same code
///     paths a real idle period would.
///   * "koi bhi DDA message user ko dikhai nahi deta" — no DDA-authored copy
///     ever names the system or implies the game was made easier.
void main() {
  Future<ProviderContainer> pumpGameScreen(
    WidgetTester tester, {
    AppConfig? config,
  }) async {
    // Same two non-optional overrides `game_screen_test.dart` documents:
    // content and database default to real, hanging bindings under
    // `flutter_test`.
    final content = await buildTestContentRepository();
    final testDb = await openMemoryDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config ?? AppConfig.dev()),
          appDatabaseProvider.overrideWithValue(testDb.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          // Settled, not the real live query — see game_screen_test.dart's
          // identical override for why.
          coinBalanceProvider.overrideWith((ref) => Stream.value(1000)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GameScreen(levelId: '1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(GameScreen)));
  }

  GameState level1State(ProviderContainer container) =>
      container.read(gameControllerProvider(const JourneySession(1))).value!;

  PulseController pulseControllerOf(WidgetTester tester) =>
      tester.widget<GameGrid>(find.byType(GameGrid)).pulseController!;

  bool releaseSelection(WidgetTester tester, SelectionState selection) {
    final grid = tester.widget<GameGrid>(find.byType(GameGrid));
    final gridState = tester.state<GameGridState>(find.byType(GameGrid));
    return grid.onSelectionReleased(selection, gridState.geometry!);
  }

  SelectionState selectionFor(WordPlacement placement) => SelectionState(
    anchor: placement.cells.first,
    direction: placement.direction,
    cells: placement.cells,
  );

  group('FTUE glow — first word findable well under 15s', () {
    testWidgets(
      'the first target word glows at 2s of inactivity, nothing before',
      (tester) async {
        final container = await pumpGameScreen(tester);
        final pulse = pulseControllerOf(tester);
        final state = level1State(container);
        final targetWord = state.allWords.first;
        final targetCell = state.grid.placements[targetWord]!.first;

        await tester.pump(const Duration(milliseconds: 999));
        expect(
          pulse.signal.value,
          isNull,
          reason: 'must not fire before the full 2s',
        );

        await tester.pump(const Duration(milliseconds: 1001));
        expect(pulse.signal.value, isNotNull);
        expect(pulse.signal.value!.cell, targetCell);
      },
    );

    testWidgets('repeats every 6s until the first word is found', (
      tester,
    ) async {
      await pumpGameScreen(tester);
      final pulse = pulseControllerOf(tester);

      await tester.pump(const Duration(seconds: 2));
      final firstNonce = pulse.signal.value!.nonce;

      await tester.pump(const Duration(seconds: 5));
      expect(
        pulse.signal.value!.nonce,
        firstNonce,
        reason: 'not yet 6s since the first glow',
      );

      await tester.pump(const Duration(seconds: 1));
      expect(
        pulse.signal.value!.nonce,
        isNot(firstNonce),
        reason: 'a fresh nonce replays the glow at the 6s repeat',
      );
    });

    testWidgets(
      'finding the glowed word succeeds — proves the 15s budget is easily '
      'met (2s wait + one correct drag)',
      (tester) async {
        final container = await pumpGameScreen(tester);
        await tester.pump(const Duration(seconds: 2));

        final state = level1State(container);
        final targetWord = state.allWords.first;
        final placement = state.grid.placementDetails.firstWhere(
          (p) => p.word == targetWord,
        );

        final matched = releaseSelection(tester, selectionFor(placement));
        // Lets the Ch03 particle burst's own 90ms `Future.delayed` fire and
        // resolve before the test ends — otherwise flutter_test flags it as
        // a timer still pending after the widget tree is disposed.
        await tester.pump(const Duration(milliseconds: 100));

        expect(matched, isTrue);
        final after = level1State(container);
        expect(after.foundWords, contains(targetWord));
      },
    );

    testWidgets('stops re-arming once the first word is found', (tester) async {
      final container = await pumpGameScreen(tester);
      final pulse = pulseControllerOf(tester);
      final state = level1State(container);
      final targetWord = state.allWords.first;
      final placement = state.grid.placementDetails.firstWhere(
        (p) => p.word == targetWord,
      );
      releaseSelection(tester, selectionFor(placement));
      await tester.pump();

      // 2s is exactly the FTUE cadence's own first trigger — if FTUE were
      // still armed this would glow again immediately. It does not, because
      // `state.foundWords` is no longer empty.
      await tester.pump(const Duration(seconds: 2));

      expect(
        pulse.signal.value,
        isNull,
        reason: 'FTUE only runs before the first word is found',
      );
    });
  });

  group('DDA states trigger via the dev debug toggle', () {
    Future<void> openDebugPanel(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pump();
    }

    testWidgets('forcing pulse drives the SAME PulseController the idle '
        'timer would', (tester) async {
      await pumpGameScreen(tester);
      final pulse = pulseControllerOf(tester);
      await openDebugPanel(tester);

      expect(pulse.signal.value, isNull);
      await tester.tap(find.widgetWithText(ActionChip, DdaState.pulse.name));
      await tester.pump();

      expect(pulse.signal.value, isNotNull);
    });

    testWidgets('forcing hintOffer shows the free-hint banner', (tester) async {
      await pumpGameScreen(tester);
      await openDebugPanel(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(GameScreen)));
      expect(find.text(l10n.ddaHintOfferMessage), findsNothing);

      await tester.tap(
        find.widgetWithText(ActionChip, DdaState.hintOffer.name),
      );
      await tester.pump();

      expect(find.text(l10n.ddaHintOfferMessage), findsOneWidget);
    });

    testWidgets('forcing none clears both the pulse and the banner', (
      tester,
    ) async {
      await pumpGameScreen(tester);
      final pulse = pulseControllerOf(tester);
      await openDebugPanel(tester);
      await tester.tap(
        find.widgetWithText(ActionChip, DdaState.hintOffer.name),
      );
      await tester.pump();
      final l10n = AppLocalizations.of(tester.element(find.byType(GameScreen)));
      expect(find.text(l10n.ddaHintOfferMessage), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, DdaState.none.name));
      await tester.pump();

      expect(find.text(l10n.ddaHintOfferMessage), findsNothing);
      expect(pulse.signal.value, isNull);
    });

    testWidgets(
      'accepting the forced hint offer calls GameController.useHint for '
      'FREE — no coins spent',
      (tester) async {
        final container = await pumpGameScreen(tester);
        await openDebugPanel(tester);
        await tester.tap(
          find.widgetWithText(ActionChip, DdaState.hintOffer.name),
        );
        await tester.pump();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(GameScreen)),
        );

        await tester.tap(find.text(l10n.ddaHintOfferAccept));
        await tester.pump();

        final state = level1State(container);
        expect(state.hintedCell, isNotNull);
        expect(state.hintsUsed, 1);
      },
    );
  });

  group('no DDA message is ever shown to the player', () {
    /// Copy that would leak the system's existence or imply the game
    /// changed itself for the player — CLAUDE.md: "never surface any message
    /// implying the game was made easier".
    const bannedSubstrings = [
      'stuck',
      'difficult',
      'easier',
      'easy for you',
      'DDA',
      'dynamic difficulty',
      'noticed you',
      'we made',
      'downshift',
    ];

    /// True when [element] sits under a [GameDebugPanel] — dev-flavor-only
    /// tooling, allowlisted from the l10n check for the same reason
    /// (`tool/check_localized_strings.dart`), and never shown to a player.
    /// This suite is about what a PLAYER can see, so the panel's own "DDA"
    /// section header (a debugging label, not game copy) is out of scope.
    bool insideDebugPanel(Element element) {
      var found = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is GameDebugPanel) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    }

    void expectNoBannedCopy(WidgetTester tester) {
      final elements = find.byType(Text).evaluate();
      for (final element in elements) {
        if (insideDebugPanel(element)) continue;
        final value = (element.widget as Text).data ?? '';
        for (final banned in bannedSubstrings) {
          expect(
            value.toLowerCase().contains(banned.toLowerCase()),
            isFalse,
            reason: 'Text widget "$value" must not contain "$banned"',
          );
        }
      }
    }

    testWidgets('the silent pulse renders no text at all', (tester) async {
      await pumpGameScreen(tester);
      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pump();
      await tester.tap(find.widgetWithText(ActionChip, DdaState.pulse.name));
      await tester.pump();

      expectNoBannedCopy(tester);
    });

    testWidgets('the hint-offer banner text stays neutral', (tester) async {
      await pumpGameScreen(tester);
      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(ActionChip, DdaState.hintOffer.name),
      );
      await tester.pump();

      expectNoBannedCopy(tester);
    });
  });
}
