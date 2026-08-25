import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/integrity.dart';

/// The HMAC scheme on its own, with no database involved.
///
/// These are the properties the row-level tests depend on. If the canonical
/// encoding below is forgeable, every table's tag is forgeable too.
void main() {
  final integrity = RowIntegrity.forInstall('install-a');

  String tag({
    String table = 'level_progress',
    String rowKey = 'en/1',
    List<Object?> fields = const [3, 500, 0, 1700000000000],
  }) => integrity.tagFor(table: table, rowKey: rowKey, fields: fields);

  group('basic behaviour', () {
    test('the same contents always produce the same tag', () {
      expect(tag(), tag());
    });

    test('a changed field changes the tag', () {
      expect(
        tag(fields: const [3, 500, 0, 1700000000000]),
        isNot(tag(fields: const [3, 501, 0, 1700000000000])),
      );
    });

    test('verify accepts its own tag and rejects a mutated one', () {
      const fields = [3, 500, 0, 1700000000000];
      final valid = tag(fields: fields);

      expect(
        integrity.verify(
          table: 'level_progress',
          rowKey: 'en/1',
          fields: fields,
          tag: valid,
        ),
        isTrue,
      );
      expect(
        integrity.verify(
          table: 'level_progress',
          rowKey: 'en/1',
          // The classic edit: a bigger best score.
          fields: const [3, 999999, 0, 1700000000000],
          tag: valid,
        ),
        isFalse,
      );
    });
  });

  group('the tag is bound to the row ADDRESS', () {
    test('a different table cannot reuse a tag', () {
      expect(tag(table: 'level_progress'), isNot(tag(table: 'daily_results')));
    });

    test('a different row key cannot reuse a tag — no copy-paste cheat', () {
      // Copying level 1's finished row onto level 50 is the cheapest cheat
      // there is; binding the tag to the key is what stops it.
      expect(tag(rowKey: 'en/1'), isNot(tag(rowKey: 'en/50')));
    });

    test('the same level in another language is a different row', () {
      expect(tag(rowKey: 'en/47'), isNot(tag(rowKey: 'ur/47')));
    });
  });

  group('canonical encoding', () {
    test('field boundaries cannot slide — length prefixing works', () {
      // With a naive `fields.join('|')` these two rows serialise identically,
      // so a tag captured from one would validate the other.
      expect(
        tag(fields: const ['a|b', 'c']),
        isNot(tag(fields: const ['a', 'b|c'])),
      );
    });

    test('an empty string and null are distinguishable', () {
      expect(tag(fields: const ['']), isNot(tag(fields: const [null])));
    });

    test('an int and its string form are distinguishable', () {
      expect(tag(fields: const [1]), isNot(tag(fields: const ['1'])));
    });

    test('a bool and its int form are distinguishable', () {
      expect(tag(fields: const [true]), isNot(tag(fields: const [1])));
    });

    test('field ORDER matters', () {
      expect(tag(fields: const [1, 2]), isNot(tag(fields: const [2, 1])));
    });

    test(
      'a non-Latin field round-trips — the tag is byte-based, not ASCII',
      () {
        expect(tag(fields: const ['کھلاڑی']), tag(fields: const ['کھلاڑی']));
        expect(
          tag(fields: const ['کھلاڑی']),
          isNot(tag(fields: const ['खिलाड़ी'])),
        );
      },
    );

    test('a double is rejected rather than silently encoded', () {
      // No column in the Ch10 schema is a float, and IEEE-754 formatting is
      // not reliably identical across platforms — a tag that only mismatches
      // on some devices is worse than a compile-time-visible failure.
      expect(() => tag(fields: const [1.5]), throwsA(isA<ArgumentError>()));
    });
  });

  group('per-install keying', () {
    test('two installs produce different tags for identical contents', () {
      // A database lifted off one phone and dropped onto another must fail
      // every row, not import a stranger's progress.
      final other = RowIntegrity.forInstall('install-b');
      expect(
        tag(),
        isNot(
          other.tagFor(
            table: 'level_progress',
            rowKey: 'en/1',
            fields: const [3, 500, 0, 1700000000000],
          ),
        ),
      );
    });

    test('the same install id rebuilds the same key', () {
      final rebuilt = RowIntegrity.forInstall('install-a');
      expect(
        rebuilt.tagFor(
          table: 'level_progress',
          rowKey: 'en/1',
          fields: const [3, 500, 0, 1700000000000],
        ),
        tag(),
      );
    });
  });

  group('tagsMatch', () {
    test('compares equal tags as equal and unequal ones as unequal', () {
      expect(RowIntegrity.tagsMatch(tag(), tag()), isTrue);
      expect(RowIntegrity.tagsMatch(tag(), '${tag()}0'), isFalse);
      expect(RowIntegrity.tagsMatch(tag(), ''), isFalse);
    });
  });
}
