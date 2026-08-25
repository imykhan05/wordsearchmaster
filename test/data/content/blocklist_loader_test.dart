import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/content/blocklist_loader.dart';
import 'package:word_search_master/domain/text/language.dart';

/// A bundle that serves canned strings, so the loader is tested without
/// depending on the shipped (deliberately incomplete) asset contents.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final contents = files[key];
    if (contents == null) throw FlutterError('missing asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(contents)));
  }
}

void main() {
  group('parse', () {
    test('reads one entry per line', () {
      expect(BlocklistLoader.parse('FOO\nBAR\nBAZ'), {'FOO', 'BAR', 'BAZ'});
    });

    test('ignores comments and blank lines', () {
      const contents = '''
# a comment
FOO


# another
BAR
''';
      expect(BlocklistLoader.parse(contents), {'FOO', 'BAR'});
    });

    test('trims surrounding whitespace', () {
      expect(BlocklistLoader.parse('  FOO  \n\tBAR\t'), {'FOO', 'BAR'});
    });

    test('an all-comment file yields an empty set', () {
      // Which is exactly the shipped state of the Urdu and Hindi lists until
      // a native speaker populates them.
      expect(BlocklistLoader.parse('# nothing yet\n# really\n'), isEmpty);
    });

    test('de-duplicates', () {
      expect(BlocklistLoader.parse('FOO\nFOO\nFOO'), hasLength(1));
    });
  });

  group('load', () {
    test('reads the per-language asset path', () {
      expect(
        BlocklistLoader.assetPathFor(Language.urdu),
        'assets/content/blocklist_ur.txt',
      );
      expect(
        BlocklistLoader.assetPathFor(Language.hindi),
        'assets/content/blocklist_hi.txt',
      );
    });

    test('loads and caches', () async {
      final bundle = _FakeBundle({
        'assets/content/blocklist_en.txt': '# head\nFOO\nBAR\n',
      });
      final loader = BlocklistLoader(bundle: bundle);

      expect(await loader.load(Language.english), {'FOO', 'BAR'});
      // Second read comes from the cache; mutating the source proves it.
      bundle.files.clear();
      expect(await loader.load(Language.english), {'FOO', 'BAR'});
    });

    test('a missing asset yields an empty set, never an exception', () async {
      // The blocklist is a polish pass over the filler. Failing to load it
      // must make grids slightly less tidy, never break a player's level.
      final loader = BlocklistLoader(bundle: _FakeBundle(const {}));

      expect(await loader.load(Language.hindi), isEmpty);
    });
  });

  test(
    'the shipped English list is populated and the others are marked TODO',
    () async {
      // Guards the honest state of the content: English is usable, Urdu and
      // Hindi are explicitly awaiting a native speaker (Ch07). If someone fills
      // those in, this test should be updated along with them.
      TestWidgetsFlutterBinding.ensureInitialized();

      final english = BlocklistLoader.parse(
        await rootBundle.loadString(
          BlocklistLoader.assetPathFor(Language.english),
        ),
      );
      expect(english, isNotEmpty);

      for (final language in [Language.urdu, Language.hindi]) {
        final contents = await rootBundle.loadString(
          BlocklistLoader.assetPathFor(language),
        );
        expect(
          contents,
          contains('REQUIRES A NATIVE'),
          reason: '${language.code} list must stay flagged until curated',
        );
      }
    },
  );
}
