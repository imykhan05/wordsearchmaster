import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_no_raw_colors.dart';

void main() {
  late Directory tempLibDir;

  setUp(() {
    tempLibDir = Directory.systemTemp.createTempSync('raw_colors_test_');
  });

  tearDown(() {
    tempLibDir.deleteSync(recursive: true);
  });

  File write(String name, String content) =>
      File('${tempLibDir.path}/$name')..writeAsStringSync(content);

  test('flags a Color(0x...) literal', () {
    write('bad.dart', 'const c = Color(0xFFE8A33D);\n');

    final violations = findRawColorViolations(tempLibDir);

    expect(violations, hasLength(1));
    expect(violations.single, contains('bad.dart'));
  });

  test('flags Color.fromARGB and Color.fromRGBO', () {
    write('argb.dart', 'const c = Color.fromARGB(255, 1, 2, 3);\n');
    write('rgbo.dart', 'const c = Color.fromRGBO(1, 2, 3, 1.0);\n');

    expect(findRawColorViolations(tempLibDir), hasLength(2));
  });

  test('flags a Material Colors.* reference', () {
    write('material.dart', 'final c = Colors.deepOrange;\n');

    expect(findRawColorViolations(tempLibDir), hasLength(1));
  });

  test('allows colours read from tokens', () {
    write('good.dart', '''
final tokens = AppTokens.of(context);
final c = tokens.colors.primary;
final d = tokens.colors.foundWord[2];
''');

    expect(findRawColorViolations(tempLibDir), isEmpty);
  });

  test('does not flag a colour named in a comment', () {
    write('commented.dart', '''
// marigold is Color(0xFFE8A33D) — defined in app_tokens.dart
final c = tokens.colors.primary;
''');

    expect(findRawColorViolations(tempLibDir), isEmpty);
  });

  test('skips the allowlisted token file', () {
    final tokenFile = write(
      'app_tokens.dart',
      'const c = Color(0xFFE8A33D);\n',
    );

    expect(
      findRawColorViolations(
        tempLibDir,
        allowlist: {tokenFile.path.replaceAll(r'\', '/')},
      ),
      isEmpty,
    );
  });

  test('skips generated files', () {
    write('thing.g.dart', 'const c = Color(0xFFE8A33D);\n');
    write('thing.freezed.dart', 'const c = Colors.red;\n');

    expect(findRawColorViolations(tempLibDir), isEmpty);
  });

  test(
    'does not false-positive on an identifier merely containing "Color"',
    () {
      write('tricky.dart', '''
final highlightColorIndex = 2;
void setColorFor(int i) {}
''');

      expect(findRawColorViolations(tempLibDir), isEmpty);
    },
  );
}
