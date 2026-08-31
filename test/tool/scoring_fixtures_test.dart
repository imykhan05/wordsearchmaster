import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/scoring/scoring.dart';

import '../../tool/generate_scoring_fixtures.dart';

/// THE DART HALF OF P14's CROSS-LANGUAGE PARITY CRITERION.
///
/// `functions/test/scoring_parity.test.ts` asserts that the TypeScript port
/// reproduces every number in `functions/test/fixtures/scoring_parity.json`.
/// That claim is only worth anything while the fixture still describes THIS
/// spec — a fixture regenerated from a stale Dart file would let both sides
/// agree on the wrong answer. So this test regenerates it in memory and
/// compares bytes.
///
/// Together the two make the loop closed: change `scoring.dart` and this test
/// fails until the fixture is regenerated; regenerate it and the TypeScript
/// test fails until the port is updated. Neither side can move alone.
void main() {
  final cases = buildCases();

  test('the committed fixture is exactly what the current spec produces', () {
    final committed = File(fixturePath).readAsStringSync();
    expect(
      render(cases),
      committed,
      reason:
          'functions/test/fixtures/scoring_parity.json is stale. Regenerate '
          'it with `dart run tool/generate_scoring_fixtures.dart`, then check '
          'whether functions/src/scoring.ts needs the same change.',
    );
  });

  test('covers the 200 random inputs the acceptance criterion names', () {
    expect(randomCaseCount, greaterThanOrEqualTo(200));
    expect(cases.length, edgeCases.length + randomCaseCount);
  });

  test('is deterministic across runs, so regenerating is a no-op in git', () {
    expect(render(buildCases()), render(buildCases()));
  });

  test('the fixture states the spec version it was generated under', () {
    final decoded = jsonDecode(
      File(fixturePath).readAsStringSync(),
    ) as Map<String, Object?>;
    expect(decoded['specVersion'], Scoring.specVersion);
  });

  test('the worked example from the spec header is case 0', () {
    // Asserted here as well as inside the generator so a reordering of
    // `edgeCases` cannot silently drop the one case the spec calls normative.
    expect(cases.first, const [
      WordFound(graphemeCount: 5),
      WordFound(graphemeCount: 4),
      WrongSelection(),
      WordFound(graphemeCount: 3),
      HintUsed(),
    ]);
    expect(Scoring.computeScore(cases.first), 103);
    expect(Scoring.computeStars(hintsUsed: 1), 2);
  });

  test('the sampled inputs actually exercise all three event types', () {
    // A generator that only ever emitted `WordFound` would still produce 200
    // "random inputs" and prove almost nothing about the port.
    final random = cases.skip(edgeCases.length).expand((events) => events);
    expect(random.whereType<WordFound>(), isNotEmpty);
    expect(random.whereType<WrongSelection>(), isNotEmpty);
    expect(random.whereType<HintUsed>(), isNotEmpty);
  });

  test('the sampled inputs reach past the combo cap', () {
    // The cap at step 6 is the one place an off-by-one in either language
    // would be invisible on short replays.
    expect(
      cases.any((events) => Scoring.maxComboIn(events) > Scoring.maxComboStep),
      isTrue,
    );
  });
}
