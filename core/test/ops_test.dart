import 'package:splitken_core/splitken_core.dart';
import 'package:test/test.dart';

Expense _rent(int cents) => Expense(
  id: 'x1',
  description: 'Rent',
  amountCents: cents,
  paidBy: 'a',
  participants: const ['a', 'b'],
);

void main() {
  test('an operation survives a trip through JSON', () {
    final op = Op(
      opId: 'o1',
      clientId: 'phone-1',
      lamport: 7,
      kind: OpKind.expense,
      expense: _rent(1000),
    );
    final back = Op.fromJson(op.withSeq(3).toJson());
    expect(back.seq, 3);
    expect(back.expense!.toJson(), op.expense!.toJson());
    expect(back.target, 'x1');
  });

  test('a malformed operation is refused with a code', () {
    for (final json in <Map<String, Object?>>[
      {'opId': 'o1', 'clientId': 'c', 'lamport': 1, 'kind': 'teleport'},
      {
        'opId': '',
        'clientId': 'c',
        'lamport': 1,
        'kind': 'delete',
        'expenseId': 'x',
      },
      {
        'opId': 'o1',
        'clientId': 'c',
        'lamport': 0,
        'kind': 'delete',
        'expenseId': 'x',
      },
      {'opId': 'o1', 'clientId': 'c', 'lamport': 1, 'kind': 'delete'},
      {
        'opId': 'o1',
        'clientId': 'c',
        'lamport': 1,
        'kind': 'member',
        'member': {'id': 'm', 'name': ' '},
      },
    ]) {
      expect(
        () => Op.fromJson(json),
        throwsA(isA<SplitError>()),
        reason: '$json',
      );
    }
  });

  test('nextLamport is 1 above the highest seen', () {
    expect(nextLamport(const []), 1);
    expect(
      nextLamport([
        Op(
          opId: 'o1',
          clientId: 'c',
          lamport: 4,
          kind: OpKind.delete,
          expenseId: 'x',
        ),
        Op(
          opId: 'o2',
          clientId: 'd',
          lamport: 9,
          kind: OpKind.delete,
          expenseId: 'y',
        ),
      ]),
      10,
    );
  });

  test(
    'validate refuses a transfer to oneself and a payer not in the group',
    () {
      final members = {'a', 'b'};
      final self = Expense(
        id: 't1',
        description: 'Back',
        amountCents: 100,
        paidBy: 'a',
        participants: const ['a'],
        method: SplitMethod.exact,
        weights: const [100],
        isTransfer: true,
      );
      expect(
        () => self.validate(members),
        throwsA(
          isA<SplitError>().having((e) => e.code, 'code', 'bad_transfer'),
        ),
      );
      final stranger = Expense(
        id: 'x',
        description: 'Tea',
        amountCents: 100,
        paidBy: 'z',
        participants: const ['a'],
      );
      expect(
        () => stranger.validate(members),
        throwsA(
          isA<SplitError>().having((e) => e.code, 'code', 'unknown_member'),
        ),
      );
    },
  );
}
