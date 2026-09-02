import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/theme/theme.dart';
import 'package:word_search_master/application/game_controller.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/grid/grid_result.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';
import 'package:word_search_master/domain/grid/selection_resolver.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/game/game_grid.dart';
import 'package:word_search_master/presentation/game/level_complete_card.dart';
import 'package:word_search_master/presentation/screens/game_screen.dart';
import 'package:word_search_master/services/audio/audio_service.dart';
import 'package:word_search_master/services/audio/combo_pitch_ladder.dart';
import 'package:word_search_master/services/haptics/haptics_service.dart';

import '../../support/fake_content.dart';
import '../../support/local_db.dart';

/// A recording double for both services — every call this test cares about
/// lands in a plain list, not a mock framework.
final class _RecordingAudioService implements AudioService {
  final List<String> allCalls = [];
  final List<int> foundCombos = [];

  @override
  Future<void> preload() async {}

  @override
  Future<void> playFound({required int combo}) async {
    allCalls.add('found:$combo');
    foundCombos.add(combo);
  }

  @override
  Future<void> playLevelComplete() async => allCalls.add('levelComplete');

  @override
  Future<void> playChestOpen() async => allCalls.add('chestOpen');

  @override
  Future<void> playButtonTap() async => allCalls.add('buttonTap');

  @override
  Future<void> playCoin() async => allCalls.add('coin');

  @override
  void setMuted(bool muted) {}

  @override
  Future<void> setMusicPlaying(bool playing) async {}
}

final class _RecordingHapticsService implements HapticsService {
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

/// Covers P07's acceptance criteria directly: 20 levels playable back to
/// back without a crash, the next level already loaded behind the result
/// card (Ch02 Zeigarnik), and no `setState` anywhere in the gameplay UI.
///
/// The `choreography (Ch03)` group below covers P09's three literal
/// acceptance criteria: a rising musical phrase across 6 consecutive finds,
/// zero feedback of any kind on a miss, and reduce-motion collapsing every
/// animation while leaving audio/haptics untouched.
void main() {
  Future<ProviderContainer> pumpGameScreen(
    WidgetTester tester, {
    AudioService? audioService,
    HapticsService? hapticsService,
    bool reduceMotion = false,
  }) async {
    // TWO OVERRIDES THAT ARE NOT OPTIONAL SINCE P11:
    //
    // 1. CONTENT. `GameController.build` now awaits `ContentRepository`
    //    (P10/P11) instead of reading a hardcoded word list. Left to its
    //    default, that resolves through `rootBundle`, whose asset reads never
    //    complete under `flutter_test`'s fake async — `pumpAndSettle` then
    //    spins until it times out, with the screen stuck on its spinner. The
    //    in-memory fixture is built OUTSIDE the pump (a real await, before
    //    the fake clock is in play) and injected already-resolved.
    //
    // 2. DATABASE. `ProgressionController.recordCompletion` writes on the
    //    level-complete transition; the default `appDatabaseProvider` opens a
    //    real `drift_flutter` connection that does not exist in a widget
    //    test. An in-memory one — the same seam every P08 repository test
    //    already opens — lets the award actually land.
    final content = await buildTestContentRepository();
    final testDb = await openMemoryDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.prod()),
          appDatabaseProvider.overrideWithValue(testDb.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          if (audioService != null)
            audioServiceProvider.overrideWithValue(audioService),
          if (hapticsService != null)
            hapticsServiceProvider.overrideWithValue(hapticsService),
        ],
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const GameScreen(levelId: '1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(GameScreen)));
  }

  /// Drives one word find through the REAL callback chain — the mounted
  /// `GameGrid`'s own `onSelectionReleased`, which is `_GameScreenState`'s
  /// private method — rather than reaching into `GameController` directly,
  /// so the audio/haptic/reveal side effects under test actually run.
  bool releaseSelection(WidgetTester tester, SelectionState selection) {
    final grid = tester.widget<GameGrid>(find.byType(GameGrid));
    final gridState = tester.state<GameGridState>(find.byType(GameGrid));
    return grid.onSelectionReleased(selection, gridState.geometry!);
  }

  SelectionState selectionFor(WordPlacement placement) {
    return SelectionState(
      anchor: placement.cells.first,
      direction: placement.direction,
      cells: placement.cells,
    );
  }

  testWidgets(
    'a found word gets a thin strike-through, not a bar covering the text',
    (tester) async {
      final container = await pumpGameScreen(tester);
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );
      final state = container
          .read(gameControllerProvider(JourneySession(1)))
          .value!;
      final placement = state.grid.placementDetails.first;

      notifier.processSelection(
        SelectionState(
          anchor: placement.cells.first,
          direction: placement.direction,
          cells: placement.cells,
        ),
      );
      await tester.pump();
      // Two separate pumps, not one 300ms pump: the chip's own strike-through
      // only STARTS 140ms after `found` flips (Ch03's correct-word sequence,
      // `_WordChipState`) — the first pump crosses that delay (firing the
      // reveal and starting its 120ms tween at progress 0 in the very same
      // frame), the second lets that tween actually run to completion.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));

      // Regression: Positioned.fill hands down tight constraints, and
      // without an Align to loosen them, the strike bar used to stretch to
      // the chip's full height and blot out the word underneath it. Scoped
      // to this one chip — every chip has its own FractionallySizedBox.
      final thisChip = find.ancestor(
        of: find.text(placement.word),
        matching: find.byType(AnimatedContainer),
      );
      final strikeBarFinder = find.descendant(
        of: thisChip,
        matching: find.byType(FractionallySizedBox),
      );
      final strikeBar = tester.widget<FractionallySizedBox>(strikeBarFinder);
      final renderedSize = tester.getSize(strikeBarFinder);

      expect(strikeBar.widthFactor, closeTo(1.0, 0.01));
      expect(
        renderedSize.height,
        lessThan(8),
        reason: 'the strike-through must stay a thin line, not fill the chip',
      );
      expect(find.text(placement.word), findsOneWidget);
    },
  );

  testWidgets(
    'levels 1 through 20 play continuously, with the next level already '
    'loaded and visible behind the result card',
    (tester) async {
      final container = await pumpGameScreen(tester);
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      for (var level = 1; level <= 20; level++) {
        final state = container
            .read(gameControllerProvider(JourneySession(1)))
            .value!;
        expect(state.level, level, reason: 'one level at a time, in order');
        expect(state.phase, GamePhase.playing);

        for (final placement in state.grid.placementDetails) {
          notifier.processSelection(
            SelectionState(
              anchor: placement.cells.first,
              direction: placement.direction,
              cells: placement.cells,
            ),
          );
        }
        await tester.pump();

        // Let the P11 award chain (streak → progress → coins → badges, all
        // real database writes) actually finish before moving on. Without
        // this, twenty levels' worth of in-flight Drift transactions are
        // still pending when the tree is torn down, which `flutter_test`
        // correctly reports as a leak. `runAsync` steps outside the fake
        // clock, which is the only way a real async I/O chain can complete.
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();

        expect(
          find.byType(LevelCompleteCard),
          findsOneWidget,
          reason: 'level $level should be complete',
        );

        final behindTheCard = container
            .read(gameControllerProvider(JourneySession(1)))
            .value!;
        expect(
          behindTheCard.level,
          level + 1,
          reason:
              'Zeigarnik: GameState already advanced before the card '
              'was dismissed',
        );
        // Not just the state — the MOUNTED grid widget is already showing
        // the next level's board, not the one that was just finished.
        final renderedGrid = tester.widget<GameGrid>(find.byType(GameGrid));
        expect(renderedGrid.cells, behindTheCard.grid.cells);
        expect(
          renderedGrid.foundWordCells,
          isEmpty,
          reason: 'the next level starts with nothing found yet',
        );

        notifier.dismissLevelComplete();
        await tester.pump();
        expect(find.byType(LevelCompleteCard), findsNothing);
      }

      expect(
        container.read(gameControllerProvider(JourneySession(1))).value!.level,
        21,
        reason: '20 levels finished back to back without throwing',
      );
    },
  );

  test('no setState in the gameplay widgets — Riverpod drives all of it', () {
    // GameGrid's own local UI concerns (the ValueNotifier-driven drag, the
    // painter cache) are P06 and already proven not to use it; re-checked
    // here because P07 edited the file to add the hint layer.
    const checked = [
      'lib/presentation/screens/game_screen.dart',
      'lib/presentation/game/game_grid.dart',
      'lib/presentation/game/level_complete_card.dart',
      'lib/presentation/game/pause_sheet.dart',
      'lib/presentation/widgets/rolling_counter.dart',
      // P09 additions — both reach for a ValueNotifier/Timer instead,
      // same as everything else in this list.
      'lib/presentation/game/found_word_reveal.dart',
      'lib/presentation/game/gesture_layer.dart',
    ];

    for (final path in checked) {
      final content = File(path).readAsStringSync();
      expect(
        content.contains('setState('),
        isFalse,
        reason: '$path must drive state through Riverpod, not setState',
      );
    }
  });

  group('choreography (Ch03) — the three literal acceptance criteria', () {
    testWidgets('6 words found consecutively play an AUDIBLY RISING phrase', (
      tester,
    ) async {
      final audio = _RecordingAudioService();
      final container = await pumpGameScreen(tester, audioService: audio);
      final state = container
          .read(gameControllerProvider(JourneySession(1)))
          .value!;
      final words = state.grid.placementDetails.take(6).toList();
      expect(
        words.length,
        6,
        reason:
            'level 1 must place at least 6 of its 8 demo words for '
            'this test to exercise the whole ladder',
      );

      for (final placement in words) {
        final matched = releaseSelection(tester, selectionFor(placement));
        expect(matched, isTrue, reason: 'placement.cells IS the word');
        // Past the 90/140/160ms particle/chip/score-roll delays each
        // release schedules, so nothing is still pending when the next
        // release starts (or the test ends).
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(audio.foundCombos, [
        1,
        2,
        3,
        4,
        5,
        6,
      ], reason: 'combo climbs by exactly one per consecutive find');

      final rates = audio.foundCombos
          .map(ComboPitchLadder.rateForCombo)
          .toList();
      for (var i = 1; i < rates.length; i++) {
        expect(
          rates[i],
          greaterThan(rates[i - 1]),
          reason: 'word ${i + 1} must sound higher than word $i',
        );
      }
    });

    testWidgets(
      'a wrong selection produces ZERO audio and ZERO haptic feedback',
      (tester) async {
        final audio = _RecordingAudioService();
        final haptics = _RecordingHapticsService();
        await pumpGameScreen(
          tester,
          audioService: audio,
          hapticsService: haptics,
        );

        // No word in `_demoWords` is 2 letters, so this can never
        // accidentally match — it is unconditionally a miss.
        final matched = releaseSelection(
          tester,
          const SelectionState(
            anchor: Cell(0, 0),
            direction: GridVector.east,
            cells: [Cell(0, 0), Cell(0, 1)],
          ),
        );
        await tester.pump();

        expect(matched, isFalse);
        expect(audio.allCalls, isEmpty, reason: 'no sound on a miss');
        expect(
          haptics.allCalls,
          isEmpty,
          reason: 'no buzz on a miss — Ch03: "no punishment feedback"',
        );
      },
    );

    testWidgets(
      'reduce-motion: the word chip flips instantly, audio/haptics still fire',
      (tester) async {
        final audio = _RecordingAudioService();
        final haptics = _RecordingHapticsService();
        final container = await pumpGameScreen(
          tester,
          audioService: audio,
          hapticsService: haptics,
          reduceMotion: true,
        );
        final state = container
            .read(gameControllerProvider(JourneySession(1)))
            .value!;
        final placement = state.grid.placementDetails.first;

        final matched = releaseSelection(tester, selectionFor(placement));
        // ONE zero-duration pump — under reduce-motion every duration
        // collapses to zero, so there is no intermediate frame to wait
        // through; a real animation would still be at progress 0 here.
        await tester.pump();

        expect(matched, isTrue);
        expect(audio.foundCombos, [
          1,
        ], reason: 'audio still fires under reduce-motion (Ch03)');
        expect(
          haptics.allCalls,
          contains('wordFound'),
          reason: 'haptics still fire under reduce-motion (Ch03)',
        );

        final thisChip = find.ancestor(
          of: find.text(placement.word),
          matching: find.byType(AnimatedContainer),
        );
        final strikeBar = tester.widget<FractionallySizedBox>(
          find.descendant(
            of: thisChip,
            matching: find.byType(FractionallySizedBox),
          ),
        );
        expect(
          strikeBar.widthFactor,
          closeTo(1.0, 0.01),
          reason: 'not a single animation runs — the strike is already done',
        );
      },
    );

    testWidgets(
      'level complete plays its audio/haptic exactly once, on the transition',
      (tester) async {
        final audio = _RecordingAudioService();
        final haptics = _RecordingHapticsService();
        final container = await pumpGameScreen(
          tester,
          audioService: audio,
          hapticsService: haptics,
        );
        final state = container
            .read(gameControllerProvider(JourneySession(1)))
            .value!;

        for (final placement in state.grid.placementDetails) {
          releaseSelection(tester, selectionFor(placement));
          await tester.pump(const Duration(milliseconds: 200));
        }

        expect(audio.allCalls.where((c) => c == 'levelComplete').length, 1);
        expect(haptics.allCalls.where((c) => c == 'levelComplete').length, 1);

        // Settling further frames (the card's own reveal timeline, still
        // running) must not fire it again.
        await tester.pump(const Duration(milliseconds: 500));
        expect(audio.allCalls.where((c) => c == 'levelComplete').length, 1);
      },
    );
  });
}
