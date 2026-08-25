// Wired into CI (.github/workflows/ci.yaml). Run locally with:
//   dart run tool/check_localized_strings.dart
//
// P03 rule: all user-facing strings go through l10n — no hardcoded strings in
// widgets. Under lib/presentation/ this flags:
//   * a literal passed straight to `Text(...)`, and
//   * a literal passed to a named argument that carries user-visible copy
//     (title:, label:, tooltip:, hintText:, semanticsLabel:, ...).
//
// SCOPE, stated honestly: it is a tripwire for the mistakes people actually
// make, not a proof of completeness. A string held in a variable, built by
// concatenation, or passed to an argument outside the list below still slips
// through. Widening it further trades false negatives for false positives,
// which is the worse failure mode for a check that gates every push.
import 'dart:io';

const _defaultPath = 'lib/presentation';

/// Dev-only surfaces that never reach a player, so their English labels are
/// not user-facing strings. Both are replaced by their owning prompts.
const _allowlist = {
  // Dev tooling, registered only on the dev flavor (P02).
  'lib/presentation/screens/style_gallery_screen.dart',
  // Scaffolding + its route-name nav buttons; each screen's real UI replaces
  // it in P07/P11/P12/P17/P21.
  'lib/presentation/widgets/stub_screen.dart',
  // Dev-flavor performance readout (P06). Its labels are units — "fps",
  // "raster" — read by whoever is profiling, never by a player.
  'lib/presentation/game/perf_overlay.dart',
  // Dev-flavor level/phase jumper (P07). Never registered outside the dev
  // flavor's widget tree, same as the Style Gallery route.
  'lib/presentation/game/game_debug_panel.dart',
};

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : _defaultPath;
  final dir = Directory(path);

  if (!dir.existsSync()) {
    stdout.writeln(
      'check_localized_strings: $path does not exist, nothing to check.',
    );
    return;
  }

  final violations = findHardcodedStrings(dir, allowlist: _allowlist);

  if (violations.isEmpty) {
    stdout.writeln(
      'check_localized_strings: OK — no hardcoded user-facing literals under $path.',
    );
    return;
  }

  stderr.writeln(
    'check_localized_strings: FAILED — user-facing strings must come from '
    'AppLocalizations.of(context), not from literals. Violations:',
  );
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}

/// Returns one `path:line: source` entry per hardcoded `Text('...')` literal.
///
/// Pure logic, no process exit, so it can be unit tested directly.
List<String> findHardcodedStrings(
  Directory dir, {
  Set<String> allowlist = const {},
}) {
  final violations = <String>[];

  final dartFiles = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.endsWith('.g.dart'))
      .where((file) => !allowlist.contains(_normalize(file.path)));

  for (final file in dartFiles) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final code = _stripComment(lines[i]);
      final matches = [
        ..._textLiteralPattern.allMatches(code),
        ..._namedArgLiteralPattern.allMatches(code),
      ];
      for (final match in matches) {
        final literal = match.group(2) ?? match.group(3) ?? '';
        if (_isTranslatable(literal)) {
          violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          break;
        }
      }
    }
  }

  violations.sort();
  return violations;
}

String _normalize(String path) => path.replaceAll(r'\', '/');

String _stripComment(String line) {
  final index = line.indexOf('//');
  return index == -1 ? line : line.substring(0, index);
}

/// `Text('literal')` or `Text("literal")`, capturing the literal.
final _textLiteralPattern = RegExp(
  '''\\bText\\s*\\(\\s*(r?)(?:'([^']*)'|"([^"]*)")''',
);

/// Named arguments that carry copy a player reads. A literal here is just as
/// unlocalized as one inside `Text(...)`.
const _userFacingArgs = [
  'title',
  'subtitle',
  'label',
  'tooltip',
  'message',
  'hintText',
  'helperText',
  'errorText',
  'labelText',
  'semanticsLabel',
];

/// `title: 'literal'`, `tooltip: "literal"`, ...
///
/// The argument name is a non-capturing group so the literal lands in the same
/// capture slots as [_textLiteralPattern] and both can share one reader.
final _namedArgLiteralPattern = RegExp(
  '\\b(?:${_userFacingArgs.join('|')})\\s*:\\s*(r?)'
  """(?:'([^']*)'|"([^"]*)")""",
);

/// A literal needs translating only if it carries actual words of its own.
/// A pure interpolation like `Text('\$score')` is data, not copy.
bool _isTranslatable(String literal) {
  final withoutInterpolation = literal
      .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
      .replaceAll(RegExp(r'\$\w+'), '');
  return RegExp('[A-Za-z]').hasMatch(withoutInterpolation);
}
