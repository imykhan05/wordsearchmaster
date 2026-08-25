import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/local/outbox_kind.dart';
import 'package:word_search_master/data/repositories/coins_repository.dart';

import '../../support/local_db.dart';

/// The balance is DERIVED, never stored (Ch10).
void main() {
  late TestDatabase opened;
  late CoinsRepository coins;

  setUp(() async {
    opened = await openMemoryDatabase();
    addTearDown(opened.database.close);
    coins = CoinsRepository(
      database: opened.database,
      integrity: opened.integrity,
      reporter: opened.reporter,
    );
  });

  Future<List<OutboxRow>> outboxRows() =>
      opened.database.select(opened.database.outbox).get();

  group('derived balance', () {
    test('an empty ledger is a zero balance', () async {
      expect(await coins.watchBalance().first, 0);
    });

    test('sums earns and spends in order', () async {
      await coins.record(delta: 30, reason: 'level_complete:en:1');
      await coins.record(delta: 45, reason: 'level_complete:en:2');
      await coins.record(delta: -20, reason: 'hint:en:2');

      expect(await coins.watchBalance().first, 55);
    });

    test('the balance can be rebuilt from the ledger alone', () async {
      await coins.record(delta: 100, reason: 'chest');
      await coins.record(delta: -35, reason: 'hint');

      final ledger = await coins.watchLedger().first;
      final replayed = ledger.fold(0, (total, row) => total + row.delta);

      expect(replayed, await coins.watchBalance().first);
      expect(replayed, 65);
    });

    test('the ledger reads newest first', () async {
      await coins.record(delta: 10, reason: 'first');
      await coins.record(delta: 20, reason: 'second');

      final ledger = await coins.watchLedger().first;
      expect(ledger.map((row) => row.reason), ['second', 'first']);
    });

    test('the balance stream emits again when a row is appended', () async {
      final emissions = <int>[];
      final subscription = coins.watchBalance().listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await coins.record(delta: 40, reason: 'level_complete:en:1');
      await pumpEventQueue();

      expect(emissions.last, 40);
    });

    test(
      'a negative balance is representable — the ledger never lies',
      () async {
        // `record` is the low-level append and does not police the balance;
        // that is `trySpend`'s job. If a refund or a server correction ever
        // pushes a player negative, the ledger must show it rather than
        // silently clamping and hiding the bug.
        await coins.record(delta: 10, reason: 'earn');
        await coins.record(delta: -25, reason: 'correction:server');

        expect(await coins.watchBalance().first, -15);
      },
    );
  });

  group('trySpend', () {
    test('spends when the balance covers it', () async {
      await coins.record(delta: 50, reason: 'earn');

      expect(await coins.trySpend(amount: 30, reason: 'hint:en:4'), isTrue);
      expect(await coins.watchBalance().first, 20);
    });

    test('spending the exact balance is allowed', () async {
      await coins.record(delta: 50, reason: 'earn');

      expect(await coins.trySpend(amount: 50, reason: 'hint'), isTrue);
      expect(await coins.watchBalance().first, 0);
    });

    test('refuses, and writes NOTHING, when short', () async {
      await coins.record(delta: 10, reason: 'earn');
      final before = await outboxRows();

      expect(await coins.trySpend(amount: 30, reason: 'hint'), isFalse);

      expect(await coins.watchBalance().first, 10);
      expect(await coins.watchLedger().first, hasLength(1));
      expect(
        await outboxRows(),
        hasLength(before.length),
        reason: 'a refused spend must not queue a submission either',
      );
    });

    test('a spend on an empty ledger is refused', () async {
      expect(await coins.trySpend(amount: 1, reason: 'hint'), isFalse);
    });
  });

  group('every movement queues its submission', () {
    test('record writes a coinsDelta outbox row', () async {
      await coins.record(delta: 25, reason: 'level_complete:ur:3');

      final rows = await outboxRows();
      expect(rows, hasLength(1));
      expect(rows.single.kind, OutboxKind.coinsDelta.name);
      expect(rows.single.payload, contains('"delta":25'));
      expect(rows.single.payload, contains('level_complete:ur:3'));
    });

    test('a successful trySpend queues one too', () async {
      await coins.record(delta: 50, reason: 'earn');
      await coins.trySpend(amount: 20, reason: 'hint');

      expect(await outboxRows(), hasLength(2));
    });

    test('ledger rows and outbox rows stay one to one', () async {
      for (var i = 1; i <= 5; i++) {
        await coins.record(delta: i * 10, reason: 'earn:$i');
      }

      expect(await coins.watchLedger().first, hasLength(5));
      expect(await outboxRows(), hasLength(5));
    });
  });

  group('ids', () {
    test('are allocated monotonically, which the tag depends on', () async {
      await coins.record(delta: 10, reason: 'a');
      await coins.record(delta: 20, reason: 'b');
      await coins.record(delta: 30, reason: 'c');

      final ledger = await coins.watchLedger().first;
      expect(ledger.map((row) => row.id), [3, 2, 1]);
    });
  });
}
