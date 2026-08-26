import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/content/blocklist_parser.dart';

void main() {
  test('reads one entry per line', () {
    expect(BlocklistParser.parse('FOO\nBAR\nBAZ'), {'FOO', 'BAR', 'BAZ'});
  });

  test('ignores comments and blank lines', () {
    const contents = '''
# a comment
FOO


# another
BAR
''';
    expect(BlocklistParser.parse(contents), {'FOO', 'BAR'});
  });

  test('trims surrounding whitespace', () {
    expect(BlocklistParser.parse('  FOO  \n\tBAR\t'), {'FOO', 'BAR'});
  });

  test('an all-comment file yields an empty set', () {
    expect(BlocklistParser.parse('# nothing yet\n# really\n'), isEmpty);
  });

  test('de-duplicates', () {
    expect(BlocklistParser.parse('FOO\nFOO\nFOO'), hasLength(1));
  });

  test('an empty string yields an empty set', () {
    expect(BlocklistParser.parse(''), isEmpty);
  });
}
