// Wired into CI (.github/workflows/ci.yaml). Run locally with:
//   dart run tool/check_domain_purity.dart
//
// lib/domain/ must be pure Dart — see CLAUDE.md → Architecture. This script
// fails the build if any file under it imports or exports package:flutter.
import 'dart:io';

const _defaultDomainPath = 'lib/domain';

void main(List<String> args) {
  final domainPath = args.isNotEmpty ? args.first : _defaultDomainPath;
  final domainDir = Directory(domainPath);

  if (!domainDir.existsSync()) {
    stdout.writeln(
      'check_domain_purity: $domainPath does not exist, nothing to check.',
    );
    return;
  }

  final violations = findFlutterImportViolations(domainDir);

  if (violations.isEmpty) {
    stdout.writeln(
      'check_domain_purity: OK — no package:flutter import under $domainPath.',
    );
    return;
  }

  stderr.writeln(
    'check_domain_purity: FAILED — $domainPath must be pure Dart '
    '(no package:flutter import/export). Violations:',
  );
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}

/// Returns one human-readable `path:line: source` entry per offending
/// import/export of `package:flutter` (or any of its libraries) found under
/// [domainDir]. Pure logic, no process exit — kept separate from [main] so
/// it can be unit tested directly (see test/tool/check_domain_purity_test.dart).
List<String> findFlutterImportViolations(Directory domainDir) {
  final violations = <String>[];

  final dartFiles = domainDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));

  for (final file in dartFiles) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (_isFlutterImportOrExport(lines[i])) {
        violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
  }

  violations.sort();
  return violations;
}

final _importExportPattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
);

bool _isFlutterImportOrExport(String line) {
  final match = _importExportPattern.firstMatch(line);
  if (match == null) return false;
  final target = match.group(1)!;
  return target == 'package:flutter' || target.startsWith('package:flutter/');
}
