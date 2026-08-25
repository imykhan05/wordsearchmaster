import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_localized_strings.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localized_strings_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File write(String name, String content) =>
      File('${tempDir.path}/$name')..writeAsStringSync(content);

  test('flags a single-quoted Text literal', () {
    write('bad.dart', "Widget b() => Text('Settings');\n");

    final violations = findHardcodedStrings(tempDir);

    expect(violations, hasLength(1));
    expect(violations.single, contains('bad.dart'));
  });

  test('flags a double-quoted Text literal', () {
    write('bad2.dart', 'Widget b() => Text("Settings");\n');

    expect(findHardcodedStrings(tempDir), hasLength(1));
  });

  test('allows a localized lookup', () {
    write('good.dart', '''
Widget b(BuildContext context) =>
    Text(AppLocalizations.of(context).navSettings);
''');

    expect(findHardcodedStrings(tempDir), isEmpty);
  });

  test('allows a variable', () {
    write('var.dart', 'Widget b(String title) => Text(title);\n');

    expect(findHardcodedStrings(tempDir), isEmpty);
  });

  test('allows a pure interpolation — that is data, not copy', () {
    write('interp.dart', r"Widget b(int score) => Text('$score');");
    write('interp2.dart', r"Widget b(Level l) => Text('${l.id}');");

    expect(findHardcodedStrings(tempDir), isEmpty);
  });

  test('flags a literal that mixes real words with interpolation', () {
    write('mixed.dart', r"Widget b(int n) => Text('Level $n');");

    expect(findHardcodedStrings(tempDir), hasLength(1));
  });

  test('ignores a Text literal inside a comment', () {
    write('commented.dart', """
// was Text('Settings') before l10n landed
Widget b(BuildContext context) => Text(AppLocalizations.of(context).navSettings);
""");

    expect(findHardcodedStrings(tempDir), isEmpty);
  });

  test('allows punctuation-only literals', () {
    write('punct.dart', "Widget b() => Text('·');\n");

    expect(findHardcodedStrings(tempDir), isEmpty);
  });

  test('flags a literal passed to a user-facing named argument', () {
    // The mistake that slipped past an earlier, Text()-only version of this
    // check: the copy is just as unlocalized one constructor further out.
    write('named.dart', "Widget b() => StubScreen(title: 'Home');\n");

    expect(findHardcodedStrings(tempDir), hasLength(1));
  });

  test('flags each user-facing argument name', () {
    for (final arg in const [
      'title',
      'subtitle',
      'label',
      'tooltip',
      'message',
      'hintText',
      'semanticsLabel',
    ]) {
      final dir = Directory.systemTemp.createTempSync('arg_$arg');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/w.dart').writeAsStringSync("W($arg: 'Settings');\n");

      expect(findHardcodedStrings(dir), hasLength(1), reason: arg);
    }
  });

  test('allows a localized value in a named argument', () {
    write('named_ok.dart', '''
Widget b(BuildContext context) =>
    StubScreen(title: AppLocalizations.of(context).navHome);
''');

    expect(findHardcodedStrings(tempDir), isEmpty);
  });

  test('does not flag an unrelated named argument', () {
    // `fontFamily:` and friends are not player-visible copy.
    write('other.dart', "W(fontFamily: 'NotoSans', debugLabel: 'x');\n");

    expect(findHardcodedStrings(tempDir), isEmpty);
  });

  test('respects the allowlist for dev-only surfaces', () {
    final devFile = write('style_gallery_screen.dart', "Text('Spacing');\n");

    expect(
      findHardcodedStrings(
        tempDir,
        allowlist: {devFile.path.replaceAll(r'\', '/')},
      ),
      isEmpty,
    );
  });

  test('skips generated files', () {
    write('thing.g.dart', "Text('Generated');\n");

    expect(findHardcodedStrings(tempDir), isEmpty);
  });

  test('reports every offending file, sorted', () {
    write('z.dart', "Text('Zebra');\n");
    write('a.dart', "Text('Apple');\n");

    final violations = findHardcodedStrings(tempDir);

    expect(violations, hasLength(2));
    expect(violations.first, contains('a.dart'));
    expect(violations.last, contains('z.dart'));
  });
}
