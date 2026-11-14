// Runs against a real PostgreSQL when SPLITKEN_TEST_DATABASE_URL is set, such
// as postgresql://postgres@localhost:5432/splitken_test?sslmode=disable. The
// tables in that database are dropped and made again.
@TestOn('vm')
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:splitken_core/splitken_core.dart';
import 'package:splitken_server/splitken_server.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final url = Platform.environment['SPLITKEN_TEST_DATABASE_URL'];
  final skip = url == null || url.isEmpty
      ? 'SPLITKEN_TEST_DATABASE_URL is not set'
      : null;

  late PostgresStore store;

  setUp(() async {
    final conn = await Connection.openFromUrl(url!);
    await conn.execute('DROP TABLE IF EXISTS ops, groups');
    await conn.close();
    store = await PostgresStore.open(url);
  });

  tearDown(() => store.close());

  Group trip() => Group(
    id: 'g1',
    name: 'Tofino trip',
    currency: 'CAD',
    founders: const [Member('m1', 'Ana'), Member('m2', 'Ben')],
  );

  test('a group and its operations outlive the store', () async {
    await store.createGroup(trip());
    final ops = [
      Op.fromJson(memberOp('o1', 'phone', 1, 'phone-1', 'Cai')),
      Op.fromJson(
        expenseOp('o2', 'phone', 2, 'x1', 900, 'm1', ['m1', 'm2', 'phone-1']),
      ),
    ];
    expect(await store.append('g1', ops, (_, _) {}), 2);
    await store.close();

    store = await PostgresStore.open(url!);
    final group = (await store.group('g1'))!;
    expect(group.founders, trip().founders);
    final stored = await store.opsSince('g1', 0);
    expect(stored.map((o) => o.opId), ['o1', 'o2']);
    expect(stored.map((o) => o.seq).toSet().length, 2);
    final state = fold(group.founders, stored);
    expect(balances(state.members, state.expenses), {
      'm1': 600,
      'm2': -300,
      'phone-1': -300,
    });
    expect(await store.opsSince('g1', stored.first.seq!), hasLength(1));
  }, skip: skip);

  test('a refused check stores nothing', () async {
    await store.createGroup(trip());
    final op = Op.fromJson(
      expenseOp('o1', 'phone', 1, 'x1', 900, 'm1', ['m1']),
    );
    await expectLater(
      store.append('g1', [op], (_, _) => throw StateError('no')),
      throwsStateError,
    );
    expect(await store.opsSince('g1', 0), isEmpty);
  }, skip: skip);

  test('the same batch sent by 5 requests at once is stored once', () async {
    await store.createGroup(trip());
    final ops = [
      for (var i = 0; i < 20; i++)
        Op.fromJson(
          expenseOp('o$i', 'phone', i + 1, 'x$i', 100, 'm1', ['m1', 'm2']),
        ),
    ];
    final counts = await Future.wait([
      for (var i = 0; i < 5; i++) store.append('g1', ops, (_, _) {}),
    ]);
    expect(counts.fold<int>(0, (a, b) => a + b), 20);
    expect(await store.opsSince('g1', 0), hasLength(20));
  }, skip: skip);

  test('the API works the same on PostgreSQL', () async {
    final api = buildApi(store, newId: () => 'g2');
    final (status, created) = await call(api, 'POST', '/v1/groups', {
      'name': 'Rent',
      'currency': 'CAD',
      'members': ['Ana', 'Ben'],
    });
    expect((status, created['id']), (201, 'g2'));
    final (s2, synced) = await call(api, 'POST', '/v1/groups/g2/sync', {
      'since': 0,
      'ops': [
        expenseOp('o1', 'phone', 1, 'x1', 2000, 'm2', ['m1', 'm2']),
      ],
    });
    expect(
      (s2, synced['stored'], (synced['ops']! as List).length),
      (200, 1, 1),
    );
    final (_, bal) = await call(api, 'GET', '/v1/groups/g2/balances');
    expect(bal['net'], {'m1': -1000, 'm2': 1000});
  }, skip: skip);
}
