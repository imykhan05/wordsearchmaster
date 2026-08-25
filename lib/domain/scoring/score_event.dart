/// Something that happened during a level and affects the score.
///
/// The score is computed by REPLAYING these in order rather than from
/// aggregate counters. That is deliberate, and it is what makes Ch08's
/// server-authoritative scoring possible: the combo ladder depends on the
/// *sequence* of correct and wrong selections, so a total derived only from
/// "words found" and "hints used" could not reproduce it. The client submits
/// its work; the Cloud Function replays that work and computes the number
/// itself, never reading the client's.
///
/// Mirrored in TypeScript as a discriminated union — see the spec header in
/// `scoring.dart`.
sealed class ScoreEvent {
  const ScoreEvent();
}

/// A word was correctly traced.
final class WordFound extends ScoreEvent {
  const WordFound({required this.graphemeCount});

  /// Cells the word occupied — grapheme clusters, never code points, so a
  /// Hindi word scores by aksharas and not by code units.
  final int graphemeCount;

  @override
  bool operator ==(Object other) =>
      other is WordFound && other.graphemeCount == graphemeCount;

  @override
  int get hashCode => graphemeCount.hashCode;

  @override
  String toString() => 'WordFound($graphemeCount)';
}

/// A selection was released that did not spell a remaining word.
///
/// Costs no points — punishing a wrong guess drives casual players away
/// (Ch03) — but it does break the combo.
final class WrongSelection extends ScoreEvent {
  const WrongSelection();

  @override
  bool operator ==(Object other) => other is WrongSelection;

  @override
  int get hashCode => 0x5e1ec7;

  @override
  String toString() => 'WrongSelection()';
}

/// A hint was consumed. Free anti-frustration hints (Ch02's DDA) are NOT
/// recorded here — only hints the player chose to spend on.
final class HintUsed extends ScoreEvent {
  const HintUsed();

  @override
  bool operator ==(Object other) => other is HintUsed;

  @override
  int get hashCode => 0x81a7;

  @override
  String toString() => 'HintUsed()';
}
