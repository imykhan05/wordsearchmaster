import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_domain_purity.dart';

void main() {
  late Directory tempDomainDir;

  setUp(() {
    tempDomainDir = Directory.systemTemp.createTempSync('domain_purity_test_');
  });

  tearDown(() {
    tempDomainDir.deleteSync(recursive: true);
  });

  test('flags a package:flutter import', () {
    File('${tempDomainDir.path}/bad.dart').writeAsStringSync('''
import 'package:flutter/material.dart';

class Bad {}
''');

    final violations = findFlutterImportViolations(tempDomainDir);

    expect(violations, hasLength(1));
    expect(violations.single, contains('bad.dart'));
    expect(violations.single, contains('package:flutter/material.dart'));
  });

  test('flags a bare package:flutter import', () {
    File('${tempDomainDir.path}/bad_bare.dart').writeAsStringSync('''
import 'package:flutter';
''');

    expect(findFlutterImportViolations(tempDomainDir), hasLength(1));
  });

  test('flags a package:flutter export', () {
    File('${tempDomainDir.path}/bad_export.dart').writeAsStringSync('''
export 'package:flutter/widgets.dart';
''');

    expect(findFlutterImportViolations(tempDomainDir), hasLength(1));
  });

  test('allows pure Dart and non-flutter package imports', () {
    File('${tempDomainDir.path}/good.dart').writeAsStringSync('''
import 'dart:math';
import 'package:characters/characters.dart';

class Good {}
''');

    expect(findFlutterImportViolations(tempDomainDir), isEmpty);
  });

  test('does not false-positive on a package merely containing "flutter" in its name', () {
    File('${tempDomainDir.path}/tricky.dart').writeAsStringSync('''
import 'package:flutter_lints_lookalike/thing.dart';
''');

    expect(findFlutterImportViolations(tempDomainDir), isEmpty);
  });

  test('reports every violation across multiple files, sorted', () {
    File('${tempDomainDir.path}/z_bad.dart')
        .writeAsStringSync("import 'package:flutter/material.dart';\n");
    File('${tempDomainDir.path}/a_bad.dart')
        .writeAsStringSync("import 'package:flutter/widgets.dart';\n");

    final violations = findFlutterImportViolations(tempDomainDir);

    expect(violations, hasLength(2));
    expect(violations.first, contains('a_bad.dart'));
    expect(violations.last, contains('z_bad.dart'));
  });

  test('returns empty for a directory with no dart files', () {
    expect(findFlutterImportViolations(tempDomainDir), isEmpty);
  });
}
