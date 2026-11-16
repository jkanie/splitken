import 'package:flutter_test/flutter_test.dart';
import 'package:splitken/src/api_client.dart';
import 'package:splitken/src/key_value_store.dart';
import 'package:splitken/src/library.dart';
import 'package:splitken_core/splitken_core.dart';

import 'support.dart';

void main() {
  late TestServer server;

  setUp(() => server = TestServer());

  test('totals gives what the group spent and what each member paid and owes', () async {
    final library = await Library.load(server.client(), MemoryKeyValueStore());
    final book = await library.create('Trip', 'CAD', ['Ana', 'Ben', 'Cy']);
    final dinner = Expense(
      id: 'e1',
      description: 'Dinner',
      amountCents: 1000,
      paidBy: 'm1',
      participants: const ['m1', 'm2', 'm3'],
    );
    final taxi = Expense(
      id: 'e2',
      description: 'Taxi',
      amountCents: 600,
      paidBy: 'm2',
      participants: const ['m2', 'm3'],
    );
    await book.saveExpense(dinner);
    await book.saveExpense(taxi);
    // A transfer that settles up is not spending.
    await book.recordTransfer(book.settle.first);
    expect(await book.sync(), isTrue);

    final totals = await server.client().totals(book.meta.id);
    expect(totals.currency, 'CAD');
    expect(totals.spentCents, 1600);
    expect([for (final m in totals.members) m.name], ['Ana', 'Ben', 'Cy']);
    expect([for (final m in totals.members) m.paidCents], [1000, 600, 0]);
    // Each share is the expense split as the app splits it, so the 1 cent left over from 1000 / 3 is counted once.
    final d = splitExpense(dinner);
    final t = splitExpense(taxi);
    expect([for (final m in totals.members) m.shareCents], [d[0], d[1] + t[0], d[2] + t[1]]);
    expect([for (final m in totals.members) m.shareCents].fold(0, (a, b) => a + b), 1600);
  });

  test('totals of a group that does not exist is refused', () async {
    await expectLater(
      server.client().totals('nope'),
      throwsA(isA<RefusedError>().having((e) => e.code, 'code', 'not_found')),
    );
    server.online = false;
    await expectLater(server.client().totals('nope'), throwsA(isA<OfflineError>()));
  });
}
