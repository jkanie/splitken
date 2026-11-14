import 'errors.dart';
import 'model.dart';
import 'split.dart';

/// Each member's net position in cents, in member order: what they paid
/// minus what they owe. Positive means the group owes them. The values
/// always add up to 0.
Map<String, int> balances(List<Member> members, Iterable<Expense> expenses) {
  final net = {for (final m in members) m.id: 0};
  for (final e in expenses) {
    e.validate(net.keys.toSet());
    final owed = splitExpense(e);
    net[e.paidBy] = net[e.paidBy]! + e.amountCents;
    for (var i = 0; i < owed.length; i++) {
      final p = e.participants[i];
      net[p] = net[p]! - owed[i];
    }
  }
  if (net.values.fold<int>(0, (a, b) => a + b) != 0) {
    throw SplitError('internal', 'The balances do not add up to 0.');
  }
  return net;
}
