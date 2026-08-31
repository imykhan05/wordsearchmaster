/// Generates the cross-language scoring parity fixture (P14).
///
/// ---------------------------------------------------------------------------
/// WHY A FIXTURE FILE RATHER THAN A TEST THAT RUNS BOTH LANGUAGES
///
/// P14's acceptance criterion is "Dart aur TS scoring 200 random inputs par
/// identical". The obvious reading — one test process that runs both — needs a
/// Dart VM inside the TypeScript runner or a Node process inside `flutter
/// test`, and either makes the parity check depend on a toolchain being
/// installed rather than on the two implementations agreeing. So the sides are
/// joined by a COMMITTED ARTEFACT instead:
///
///   1. This tool computes the expected numbers with the real
///      `lib/domain/scoring/scoring.dart` and writes them to
///      `functions/test/fixtures/scoring_parity.json`.
///   2. `test/tool/scoring_fixtures_test.dart` regenerates the file in memory
///      and fails if the committed bytes differ — so the fixture can never go
///      stale with respect to the Dart spec.
///   3. `functions/test/scoring_parity.test.ts` reads that file and asserts the
///      TypeScript port reproduces every number.
///
/// The loop closes: change the Dart rules and (2) fails until the fixture is
/// regenerated; regenerate it and (3) fails until the port is updated. Neither
/// side can move alone, which is the property the spec header asks for.
///
/// DETERMINISTIC BY CONSTRUCTION — one `Random(_seed)` drives every case, the
/// same discipline `GridGenerator` keeps, so re-running this tool on an
/// unchanged spec is a no-op in `git status`.
///
/// Usage: `dart run tool/generate_scoring_fixtures.dart [repoRoot]`
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/scoring/scoring.dart';

/// Where the fixture lands, relative to the repo root.
const String fixturePath = 'functions/test/fixtures/scoring_parity.json';

/// The literal count P14's acceptance criterion names.
const int randomCaseCount = 200;

/// Fixed so the "random" inputs are the same on every machine and every run.
const int _seed = 20260831;

/// Wire discriminators — the same three `ScoreEventCodec` writes, restated
/// here rather than imported because `ScoreEventCodec` lives under `data/`
/// and this tool must stay plain Dart (it runs under `dart run`, which cannot
/// resolve anything reaching `dart:ui`).
const String _wordFound = 'w';
const String _wrongSelection = 'x';
const String _hintUsed = 'h';

List<Map<String, Object?>> _encode(List<ScoreEvent> events) => [
  for (final event in events)
    switch (event) {
      WordFound(:final graphemeCount) => {'t': _wordFound, 'g': graphemeCount},
      WrongSelection() => {'t': _wrongSelection},
      HintUsed() => {'t': _hintUsed},
    },
];

/// Hand-picked cases that random sampling would hit rarely or never.
///
/// Every one of these is a place the two implementations could plausibly
/// disagree: an empty replay, a score driven below zero (the clamp), the combo
/// cap at 6 and one past it, a non-positive grapheme count (`wordScore`
/// returns 0 rather than a negative), and the worked example from the spec
/// header itself.
final List<List<ScoreEvent>> edgeCases = [
  // The spec header's worked example, verbatim: 103 points, 2 stars.
  [
    WordFound(graphemeCount: 5),
    WordFound(graphemeCount: 4),
    WrongSelection(),
    WordFound(graphemeCount: 3),
    HintUsed(),
  ],
  // Nothing happened.
  [],
  // Hints only: the floor holds at 0, never negative.
  [HintUsed(), HintUsed(), HintUsed()],
  // One word, then enough hints to go under. Still 0.
  [WordFound(graphemeCount: 2), HintUsed(), HintUsed()],
  // Exactly the combo cap, then one past it: steps 6 and 7 must both pay 20.
  [
    WordFound(graphemeCount: 1),
    WordFound(graphemeCount: 1),
    WordFound(graphemeCount: 1),
    WordFound(graphemeCount: 1),
    WordFound(graphemeCount: 1),
    WordFound(graphemeCount: 1),
    WordFound(graphemeCount: 1),
  ],
  // A hint does NOT break the combo — the ladder keeps climbing across it.
  [
    WordFound(graphemeCount: 3),
    HintUsed(),
    WordFound(graphemeCount: 3),
    HintUsed(),
    WordFound(graphemeCount: 3),
  ],
  // A wrong selection between every word: the ladder never leaves step 1.
  [
    WordFound(graphemeCount: 4),
    WrongSelection(),
    WordFound(graphemeCount: 4),
    WrongSelection(),
    WordFound(graphemeCount: 4),
  ],
  // Non-positive grapheme counts score 0, they do not subtract — and they
  // still advance the combo, which is the subtle half.
  [
    WordFound(graphemeCount: 0),
    WordFound(graphemeCount: -3),
    WordFound(graphemeCount: 2),
  ],
  // Wrong selections only: no score, no stars change, max combo 0.
  [WrongSelection(), WrongSelection()],
  // The longest realistic level: 12 words on a 12x12, no mistakes.
  [for (var i = 0; i < 12; i++) WordFound(graphemeCount: 2 + (i % 8))],
];

/// [randomCaseCount] pseudo-random replays, plus [edgeCases] ahead of them.
List<List<ScoreEvent>> buildCases() {
  final random = Random(_seed);
  final cases = <List<ScoreEvent>>[...edgeCases];

  for (var i = 0; i < randomCaseCount; i++) {
    final length = random.nextInt(40);
    cases.add([for (var j = 0; j < length; j++) _randomEvent(random)]);
  }
  return cases;
}

ScoreEvent _randomEvent(Random random) {
  final roll = random.nextInt(10);
  if (roll < 7) {
    // 1..12 covers every real word (P10 caps words at 9 graphemes) plus the
    // headroom a forged payload would reach for; 0 appears occasionally so the
    // `graphemeCount <= 0` branch is sampled rather than only asserted.
    return WordFound(graphemeCount: random.nextInt(13));
  }
  if (roll < 9) return const WrongSelection();
  return const HintUsed();
}

/// The fixture's exact bytes, so the tool and its test agree by construction.
String render(List<List<ScoreEvent>> cases) {
  final payload = {
    '_comment':
        'GENERATED by tool/generate_scoring_fixtures.dart — do not edit by '
        'hand. Expected values come from lib/domain/scoring/scoring.dart, the '
        'normative spec; functions/test/scoring_parity.test.ts asserts the '
        'TypeScript port reproduces every one of them.',
    'specVersion': Scoring.specVersion,
    'seed': _seed,
    'randomCaseCount': randomCaseCount,
    'edgeCaseCount': edgeCases.length,
    'cases': [
      for (var i = 0; i < cases.length; i++)
        {
          'id': i,
          'events': _encode(cases[i]),
          'expected': {
            'score': Scoring.computeScore(cases[i]),
            'hintsUsed': Scoring.hintsIn(cases[i]),
            'stars': Scoring.computeStars(hintsUsed: Scoring.hintsIn(cases[i])),
            'maxCombo': Scoring.maxComboIn(cases[i]),
          },
        },
    ],
  };

  return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
}

Future<void> main(List<String> args) async {
  final root = args.isNotEmpty ? args.first : '.';
  final file = File('$root/$fixturePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(render(buildCases()));

  stdout.writeln(
    'Wrote ${edgeCases.length} edge + $randomCaseCount random cases to '
    '$fixturePath (scoring spec v${Scoring.specVersion}).',
  );
}
