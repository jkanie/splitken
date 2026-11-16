import 'errors.dart';
import 'model.dart';
import 'split.dart';

/// What a group spent, in cents, and each member's part of it.
class Spending {
  const Spending(this.spentCents, this.paid, this.share);

  /// The sum of the expenses that are not transfers.
  final int spentCents;

  /// Per member id, in member order: the sum of the expenses they paid.
  final Map<String, int> paid;

  /// Per member id, in member order: the sum of their split shares.
  final Map<String, int> share;
}

/// What the group spent and each member's part of it. A transfer moves money
/// between members and is not spending, so it is left out. The paid values
/// and the share values each add up to [Spending.spentCents]. Without
/// transfers, paid minus share is each member's balance.
Spending spending(List<Member> members, Iterable<Expense> expenses) {
  final paid = {for (final m in members) m.id: 0};
  final share = {for (final m in members) m.id: 0};
  var spent = 0;
  for (final e in expenses) {
    e.validate(paid.keys.toSet());
    if (e.isTransfer) continue;
    spent += e.amountCents;
    paid[e.paidBy] = paid[e.paidBy]! + e.amountCents;
    final owed = splitExpense(e);
    for (var i = 0; i < owed.length; i++) {
      share[e.participants[i]] = share[e.participants[i]]! + owed[i];
    }
  }
  int sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);
  if (sum(paid) != spent || sum(share) != spent) {
    throw SplitError('internal', 'The spending does not add up.');
  }
  return Spending(spent, paid, share);
}
