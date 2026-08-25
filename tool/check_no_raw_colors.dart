// Wired into CI (.github/workflows/ci.yaml). Run locally with:
//   dart run tool/check_no_raw_colors.dart
//
// P02 acceptance criterion: no raw hex colour anywhere in the codebase.
// Every colour must come from AppTokens, so a palette change is one edit and
// both themes stay in sync. This fails the build if a colour literal or a
// Material `Colors.*` reference appears under lib/ outside the token file.
import 'dart:io';

const _defaultLibPath = 'lib';

/// The one file allowed to name colours directly.
const _allowlist = {'lib/app/theme/app_tokens.dart'};

void main(List<String> args) {
  final libPath = args.isNotEmpty ? args.first : _defaultLibPath;
  final libDir = Directory(libPath);

  if (!libDir.existsSync()) {
    stdout.writeln(
      'check_no_raw_colors: $libPath does not exist, nothing to check.',
    );
    return;
  }

  final violations = findRawColorViolations(libDir, allowlist: _allowlist);

  if (violations.isEmpty) {
    stdout.writeln(
      'check_no_raw_colors: OK — every colour under $libPath comes from AppTokens.',
    );
    return;
  }

  stderr.writeln(
    'check_no_raw_colors: FAILED — colours must come from AppTokens '
    '(lib/app/theme/app_tokens.dart), not from literals. Violations:',
  );
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}

/// Returns one `path:line: source` entry per raw colour found under [libDir].
///
/// Pure logic, no process exit, so it can be unit tested directly — see
/// test/tool/check_no_raw_colors_test.dart.
List<String> findRawColorViolations(
  Directory libDir, {
  Set<String> allowlist = const {},
}) {
  final violations = <String>[];

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      // Generated code is not hand-written, so it is not a style violation to
      // fix — and it is regenerated on every build anyway.
      .where((file) => !_isGenerated(file.path))
      .where((file) => !allowlist.contains(_normalize(file.path)));

  for (final file in dartFiles) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final code = _stripComment(lines[i]);
      if (_rawColorPattern.hasMatch(code)) {
        violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
  }

  violations.sort();
  return violations;
}

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.drift.dart');

String _normalize(String path) => path.replaceAll(r'\', '/');

/// Drops a trailing `//` comment so prose mentioning a colour does not trip
/// the check. Naive about `//` inside a string literal, which is fine here:
/// the alternative is a false negative, and colours are not URLs.
String _stripComment(String line) {
  final index = line.indexOf('//');
  return index == -1 ? line : line.substring(0, index);
}

final _rawColorPattern = RegExp(
  // Color(0xFF...) / Color.fromARGB(...) / Color.fromRGBO(...)
  r'\bColor\s*\(\s*0x'
  r'|\bColor\s*\.\s*from(ARGB|RGBO)\s*\('
  // Colors.red, Colors.black54, ...  (Material's palette is still a hardcoded
  // colour as far as the design system is concerned)
  r'|\bColors\s*\.\s*[a-zA-Z]',
);
