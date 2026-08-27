import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/outbox_kind.dart';
import 'package:word_search_master/data/repositories/daily_repository.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/grid/grid_generator.dart';
import 'package:word_search_master/domain/progression/daily_puzzle.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/text/language.dart';

import '../../support/fake_content.dart';
import '../../support/local_db.dart';

/// P11 acceptance criterion 1: "Daily challenge airplane mode mein khelta
/// hai" — the Daily Challenge is fully playable with no network.
///
/// ---------------------------------------------------------------------------
/// HOW A TEST PROVES "AIRPLANE MODE"
///
/// Not by toggling a flag — there is no network layer to toggle yet (P13/P14
/// bring Firebase). The claim is stronger and more checkable than that: NO
/// PART OF THE DAILY PATH HAS A NETWORK CALL TO MAKE. So this file walks the
/// whole path end to end against local pieces only, and asserts the two
/// properties that make the offline claim structural rather than incidental:
///
///   * the PUZZLE is computed on-device from the UTC date (P10's seed →
///     `DailyPuzzle` → `GridGenerator`), so three "devices" that never talk
///     produce the identical board;
///   * the RESULT is recorded locally and QUEUED in the outbox, so finishing
///     it never awaits a server — the submission leaves whenever a connection
///     next exists.
void main() {
  final today = DayKey.parse('2026-08-26');

  group('the puzzle is computed on-device, so three devices agree', () {
    test(
      'same day + same language = byte-identical grid, no coordination',
      () async {
        // Three independently-built repositories, each reading its own canned
        // asset bundle — the cheapest honest stand-in for three devices that
        // have never contacted each other or a server.
        final grids = <List<List<String>>>[];

        for (var device = 0; device < 3; device++) {
          final content = await buildTestContentRepository();
          final definition = DailyPuzzle.definitionFor(
            day: today,
            language: Language.english,
            seed: content.getDailySeed(today.utcMidnight, Language.english),
            categories: content.categoriesFor(Language.english),
          );
          final words = content.getWordsForLevel(definition);

          grids.add(
            GridGenerator.generate(
              seed: definition.seed,
              size: definition.gridSize,
              words: [for (final entry in words) entry.word],
              lang: definition.language,
              allowedDirections: GridDirections.forLanguage(
                definition.language,
                definition.directionTier,
              ),
            ).cells,
          );
        }

        expect(grids[1], grids[0]);
        expect(grids[2], grids[0]);
      },
    );

    test('a different UTC day is a different puzzle', () async {
      final content = await buildTestContentRepository();

      int seedFor(DayKey day) =>
          content.getDailySeed(day.utcMidnight, Language.english);

      expect(seedFor(today), isNot(seedFor(today.next)));
    });

    test(
      'the shape is fixed for everyone — not borrowed from the curve',
      () async {
        final content = await buildTestContentRepository();

        for (final language in Language.values) {
          final definition = DailyPuzzle.definitionFor(
            day: today,
            language: language,
            seed: content.getDailySeed(today.utcMidnight, language),
            categories: content.categoriesFor(language),
          );

          expect(definition.gridSize, DailyPuzzle.gridSize);
          expect(definition.wordCount, DailyPuzzle.wordCount);
          expect(definition.directionTier, DailyPuzzle.directionTier);
          expect(
            definition.id,
            DailyPuzzle.levelId,
            reason: 'never a real journey level number',
          );
        }
      },
    );

    test('an empty category list degrades rather than throwing', () {
      final definition = DailyPuzzle.definitionFor(
        day: today,
        language: Language.english,
        seed: 1,
        categories: const [],
      );

      expect(definition.categoryPool, isEmpty);
    });
  });

  group('the result is recorded locally and queued, never posted', () {
    test(
      'finishing writes a daily_results row AND an outbox row, atomically',
      () async {
        final db = await openMemoryDatabase();
        addTearDown(db.database.close);
        final repo = DailyRepository(
          database: db.database,
          integrity: db.integrity,
          reporter: db.reporter,
        );

        final recorded = await repo.recordDailyComplete(
          day: today,
          language: Language.english,
          score: 240,
          stars: 3,
          events: const [
            WordFound(graphemeCount: 5),
            WordFound(graphemeCount: 4),
          ],
        );

        expect(recorded, isTrue);

        final result = await repo.result(today, Language.english);
        expect(result, isNotNull);
        expect(result!.score, 240);
        expect(result.stars, 3);

        final outbox = await db.database.select(db.database.outbox).get();
        expect(outbox, hasLength(1));
        expect(outbox.single.kind, OutboxKind.dailyResult.name);
        expect(
          outbox.single.payload,
          contains('"events"'),
          reason:
              'the ordered events, for the server to replay — never the client'
              's own total (CLAUDE.md → never write scores directly)',
        );
      },
    );

    test('ONE ATTEMPT PER DAY: a second completion writes nothing', () async {
      final db = await openMemoryDatabase();
      addTearDown(db.database.close);
      final repo = DailyRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );

      await repo.recordDailyComplete(
        day: today,
        language: Language.english,
        score: 100,
        stars: 1,
        events: const [WordFound(graphemeCount: 3)],
      );

      final second = await repo.recordDailyComplete(
        day: today,
        language: Language.english,
        score: 999,
        stars: 3,
        events: const [WordFound(graphemeCount: 9)],
      );

      expect(second, isFalse);

      final result = await repo.result(today, Language.english);
      expect(
        result!.score,
        100,
        reason:
            'the FIRST attempt is the attempt — a best-of write would let a '
            'player grind the daily leaderboard',
      );

      final outbox = await db.database.select(db.database.outbox).get();
      expect(outbox, hasLength(1), reason: 'no second submission queued');
    });

    test(
      'hasPlayed flips exactly once, for exactly that day and language',
      () async {
        final db = await openMemoryDatabase();
        addTearDown(db.database.close);
        final repo = DailyRepository(
          database: db.database,
          integrity: db.integrity,
          reporter: db.reporter,
        );

        expect(await repo.hasPlayed(today, Language.english), isFalse);

        await repo.recordDailyComplete(
          day: today,
          language: Language.english,
          score: 10,
          stars: 1,
          events: const [],
        );

        expect(await repo.hasPlayed(today, Language.english), isTrue);
        expect(
          await repo.hasPlayed(today, Language.urdu),
          isFalse,
          reason: 'three languages, three different puzzles on the same date',
        );
        expect(await repo.hasPlayed(today.next, Language.english), isFalse);
      },
    );

    test('each language keeps its own result for the same date', () async {
      final db = await openMemoryDatabase();
      addTearDown(db.database.close);
      final repo = DailyRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );

      for (final language in Language.values) {
        await repo.recordDailyComplete(
          day: today,
          language: language,
          score: 100 + language.index,
          stars: 2,
          events: const [],
        );
      }

      for (final language in Language.values) {
        final result = await repo.result(today, language);
        expect(result!.score, 100 + language.index);
      }
    });

    test('history reads newest-first', () async {
      final db = await openMemoryDatabase();
      addTearDown(db.database.close);
      final repo = DailyRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );

      for (var i = 0; i < 3; i++) {
        await repo.recordDailyComplete(
          day: today.addDays(i),
          language: Language.english,
          score: i,
          stars: 1,
          events: const [],
        );
      }

      final all = await repo.watchAll(Language.english).first;
      expect(all.map((row) => row.date).toList(), [
        today.addDays(2).toString(),
        today.addDays(1).toString(),
        today.toString(),
      ]);
    });
  });
}
