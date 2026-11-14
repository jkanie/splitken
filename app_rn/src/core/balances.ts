import { SplitError } from './errors';
import { type Expense, type Member, validateExpense } from './model';
import { splitExpense } from './split';

/**
 * Each member's net position in cents, in member order: what they paid minus
 * what they owe. Positive means the group owes them. The values add up to 0.
 */
export function balances(
  members: readonly Member[],
  expenses: Iterable<Expense>,
): Map<string, number> {
  const net = new Map(members.map((m) => [m.id, 0]));
  const ids = new Set(net.keys());
  for (const e of expenses) {
    validateExpense(e, ids);
    const owed = splitExpense(e);
    net.set(e.paidBy, net.get(e.paidBy)! + e.amountCents);
    owed.forEach((cents, i) => {
      const p = e.participants[i];
      net.set(p, net.get(p)! - cents);
    });
  }
  let total = 0;
  for (const v of net.values()) total += v;
  if (total !== 0) throw new SplitError('internal', 'The balances do not add up to 0.');
  return net;
}
