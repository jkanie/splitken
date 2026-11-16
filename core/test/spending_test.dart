import 'package:splitken_core/splitken_core.dart';
import 'package:test/test.dart';

const _members = [Member('a', 'Ana'), Member('b', 'Ben'), Member('c', 'Cy')];

Expense _e(
  String id,
  int cents,
  String paidBy,
  List<String> who, {
  bool transfer = false,
}) => Expense(
  id: id,
  description: id,
  amountCents: cents,
  paidBy: paidBy,
  participants: who,
  // A transfer is an exact split with 1 weight equal to its amount.
  method: transfer ? SplitMethod.exact : SplitMethod.equal,
  weights: transfer ? [cents] : const [],
  isTransfer: transfer,
);

void main() {
  test(
    'spending counts what each member paid and owes, transfers left out',
    () {
      final dinner = _e('e1', 1000, 'a', ['a', 'b', 'c']);
      final taxi = _e('e2', 600, 'b', ['b', 'c']);
      final s = spending(_members, [
        dinner,
        taxi,
        _e('t1', 300, 'c', ['a'], transfer: true),
      ]);
      expect(s.spentCents, 1600);
      expect(s.paid, {'a': 1000, 'b': 600, 'c': 0});
      final d = splitExpense(dinner);
      final t = splitExpense(taxi);
      expect(s.share, {'a': d[0], 'b': d[1] + t[0], 'c': d[2] + t[1]});
      expect(s.share.keys, ['a', 'b', 'c']);
    },
  );

  test('without transfers, paid minus share is the balance', () {
    final expenses = [
      _e('e1', 1001, 'a', ['a', 'b', 'c']),
      _e('e2', 250, 'c', ['b']),
    ];
    final s = spending(_members, expenses);
    final net = balances(_members, expenses);
    for (final m in _members) {
      expect(s.paid[m.id]! - s.share[m.id]!, net[m.id], reason: m.name);
    }
  });

  test('no expense spends nothing, and a stranger is refused', () {
    final s = spending(_members, []);
    expect([
      s.spentCents,
      ...s.paid.values,
      ...s.share.values,
    ], everyElement(0));
    expect(
      () => spending(_members, [
        _e('e1', 100, 'z', ['a']),
      ]),
      throwsA(isA<SplitError>()),
    );
  });
}
