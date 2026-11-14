import 'package:flutter_test/flutter_test.dart';
import 'package:splitken/src/api_client.dart';
import 'package:splitken/src/group_book.dart';
import 'package:splitken/src/key_value_store.dart';
import 'package:splitken/src/library.dart';
import 'package:splitken_core/splitken_core.dart';

import 'support.dart';

Expense dinner(String id, int cents, {String paidBy = 'm1'}) => Expense(
  id: id,
  description: 'Dinner',
  amountCents: cents,
  paidBy: paidBy,
  participants: const ['m1', 'm2', 'm3'],
);

void main() {
  late TestServer server;

  setUp(() => server = TestServer());

  Future<Library> device([MemoryKeyValueStore? store]) =>
      Library.load(server.client(), store ?? MemoryKeyValueStore());

  test('an expense made offline is kept and sent on the next sync', () async {
    final a = await device();
    final book = await a.create('Trip', 'CAD', ['Ana', 'Ben', 'Cy']);
    server.online = false;
    await book.saveExpense(dinner('e1', 1000));
    expect(book.net, {'m1': 666, 'm2': -333, 'm3': -333});
    expect(await book.sync(), isFalse);
    expect(book.pending, hasLength(1));
    expect(book.lastProblem, startsWith('Offline'));

    server.online = true;
    expect(await book.sync(), isTrue);
    expect(book.pending, isEmpty);
    expect(book.confirmed, hasLength(1));
    expect(book.seq, 1);
    expect(book.lastProblem, isNull);
  });

  test('2 devices that edit the same expense offline end up the same', () async {
    final a = await device();
    final b = await device();
    final onA = await a.create('Flat', 'EUR', ['Ana', 'Ben', 'Cy']);
    final onB = await b.join(onA.meta.id);
    await onA.saveExpense(dinner('e1', 900));
    await onA.sync();
    await onB.sync();
    expect(onB.state.expenses.single.amountCents, 900);

    server.online = false;
    await onA.saveExpense(dinner('e1', 1200));
    await onB.saveExpense(dinner('e1', 1500, paidBy: 'm2'));
    await onB.addMember('Di');
    server.online = true;
    await onA.sync();
    await onB.sync();
    await onA.sync();

    expect(onA.pending, isEmpty);
    expect(onB.pending, isEmpty);
    expect(onA.net, onB.net);
    expect(onA.state.members.map((m) => m.name), ['Ana', 'Ben', 'Cy', 'Di']);
    expect(onA.state.expenses.single.amountCents, onB.state.expenses.single.amountCents);
  });

  test('settling up records a transfer that clears the balances', () async {
    final a = await device();
    final book = await a.create('Lunch', 'CAD', ['Ana', 'Ben', 'Cy']);
    await book.saveExpense(dinner('e1', 1000));
    expect(book.settle.map((t) => (t.from, t.to, t.amountCents)), [
      ('m2', 'm1', 333),
      ('m3', 'm1', 333),
    ]);
    for (final t in book.settle) {
      await book.recordTransfer(t);
    }
    expect(book.settle, isEmpty);
    expect(book.net.values.toSet(), {0});
    expect(await book.sync(), isTrue);
  });

  test('an operation the server refuses is dropped and the rest are sent', () async {
    final a = await device();
    final book = await a.create('Club', 'CAD', ['Ana', 'Ben', 'Cy']);
    await book.saveExpense(dinner('e1', 300));
    book.pending.add(
      Op(
        opId: 'bad1',
        clientId: book.clientId,
        lamport: 50,
        kind: OpKind.member,
        member: const Member('m9', 'Not a founder'),
      ),
    );
    await book.saveExpense(dinner('e2', 600));

    expect(await book.sync(), isTrue);
    expect(book.pending, isEmpty);
    expect(book.confirmed.map((op) => op.opId), isNot(contains('bad1')));
    expect(book.state.expenses.map((e) => e.id), ['e1', 'e2']);
    expect(book.lastProblem, startsWith('A change was refused and removed'));
  });

  test('a wrong expense is refused on the device and nothing changes', () async {
    final a = await device();
    final book = await a.create('Club', 'CAD', ['Ana', 'Ben']);
    final bad = Expense(
      id: 'e1',
      description: 'Tickets',
      amountCents: 1000,
      paidBy: 'm1',
      participants: const ['m1', 'm2'],
      method: SplitMethod.percent,
      weights: const [5000, 4000],
    );
    await expectLater(book.saveExpense(bad), throwsA(isA<SplitError>()));
    expect(book.pending, isEmpty);
  });

  test('groups and pending changes survive a restart', () async {
    final store = MemoryKeyValueStore();
    final first = await device(store);
    final book = await first.create('Trip', 'CAD', ['Ana', 'Ben']);
    server.online = false;
    await book.saveExpense(
      Expense(
        id: 'e1',
        description: 'Gas',
        amountCents: 4000,
        paidBy: 'm2',
        participants: const ['m1', 'm2'],
      ),
    );

    final again = await device(store);
    expect(again.clientId, first.clientId);
    final reloaded = again.books.single;
    expect(reloaded.meta.name, 'Trip');
    expect(reloaded.pending, hasLength(1));
    expect(reloaded.net, {'m1': -2000, 'm2': 2000});
    server.online = true;
    expect(await reloaded.sync(), isTrue);
    expect(store.values[GroupBook.storageKey(book.meta.id)], contains('"pending":[]'));
  });

  test('a member name already in the group is refused, and nothing changes', () async {
    final book = await (await device()).create('Trip', 'CAD', ['Ana', 'Ben']);
    await expectLater(
      book.addMember(' ana '),
      throwsA(
        isA<SplitError>()
            .having((e) => e.code, 'code', 'bad_member')
            .having((e) => e.message, 'message', '"ana" is already a member.'),
      ),
    );
    expect(book.pending, isEmpty);
    final di = await book.addMember('Di');
    await expectLater(book.addMember('DI'), throwsA(isA<SplitError>()));
    expect(book.state.members.map((m) => m.name), ['Ana', 'Ben', 'Di']);
    expect(di.id, startsWith('${book.clientId}-'));
    // The server refuses 2 founders with 1 name in the same way.
    await expectLater(
      (await device()).create('Flat', 'CAD', ['Ana', 'ANA']),
      throwsA(
        isA<RefusedError>()
            .having((e) => e.code, 'code', 'bad_member')
            .having(
              (e) => e.message,
              'message',
              '"ANA" is listed twice. Each member needs a name of their own.',
            ),
      ),
    );
  });

  test('making a group with no network says so', () async {
    final a = await device();
    server.online = false;
    await expectLater(a.create('Trip', 'CAD', ['Ana']), throwsA(isA<Exception>()));
    expect(a.books, isEmpty);
  });
}
