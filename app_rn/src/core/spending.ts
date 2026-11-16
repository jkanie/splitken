import { SplitError } from './errors';
import { type Expense, type Member, validateExpense } from './model';
import { splitExpense } from './split';

/** What a group spent, in cents, and each member's part of it. */
export interface Spending {
  /** The sum of the expenses that are not transfers. */
  spentCents: number;
  /** Per member id, in member order: the sum of the expenses they paid. */
  paid: Map<string, number>;
  /** Per member id, in member order: the sum of their split shares. */
  share: Map<string, number>;
}

/**
 * What the group spent and each member's part of it, as the Dart core's
 * spending. A transfer moves money between members and is not spending, so it
 * is left out. The paid values and the share values each add up to
 * spentCents. Without transfers, paid minus share is each member's balance.
 */
export function spending(members: readonly Member[], expenses: Iterable<Expense>): Spending {
  const paid = new Map(members.map((m) => [m.id, 0]));
  const share = new Map(members.map((m) => [m.id, 0]));
  const ids = new Set(paid.keys());
  let spent = 0;
  for (const e of expenses) {
    validateExpense(e, ids);
    if (e.isTransfer) continue;
    spent += e.amountCents;
    paid.set(e.paidBy, paid.get(e.paidBy)! + e.amountCents);
    splitExpense(e).forEach((cents, i) => {
      const p = e.participants[i];
      share.set(p, share.get(p)! + cents);
    });
  }
  const sum = (m: Map<string, number>) => [...m.values()].reduce((a, b) => a + b, 0);
  if (sum(paid) !== spent || sum(share) !== spent) {
    throw new SplitError('internal', 'The spending does not add up.');
  }
  return { spentCents: spent, paid, share };
}
