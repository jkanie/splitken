import { type Expense, SplitError, balances, spending, splitExpense } from '../src/core';

const members = [
  { id: 'a', name: 'Ana' },
  { id: 'b', name: 'Ben' },
  { id: 'c', name: 'Cy' },
];

const e = (
  id: string,
  cents: number,
  paidBy: string,
  who: string[],
  isTransfer = false,
): Expense => ({
  id,
  description: id,
  amountCents: cents,
  paidBy,
  participants: who,
  // A transfer is an exact split with 1 weight equal to its amount.
  method: isTransfer ? 'exact' : 'equal',
  weights: isTransfer ? [cents] : [],
  isTransfer,
});

test('spending counts what each member paid and owes, transfers left out', () => {
  const dinner = e('e1', 1000, 'a', ['a', 'b', 'c']);
  const taxi = e('e2', 600, 'b', ['b', 'c']);
  const s = spending(members, [dinner, taxi, e('t1', 300, 'c', ['a'], true)]);
  expect(s.spentCents).toBe(1600);
  expect([...s.paid]).toEqual([
    ['a', 1000],
    ['b', 600],
    ['c', 0],
  ]);
  const d = splitExpense(dinner);
  const t = splitExpense(taxi);
  expect([...s.share]).toEqual([
    ['a', d[0]],
    ['b', d[1] + t[0]],
    ['c', d[2] + t[1]],
  ]);
});

test('without transfers, paid minus share is the balance', () => {
  const expenses = [e('e1', 1001, 'a', ['a', 'b', 'c']), e('e2', 250, 'c', ['b'])];
  const s = spending(members, expenses);
  const net = balances(members, expenses);
  for (const m of members) expect(s.paid.get(m.id)! - s.share.get(m.id)!).toBe(net.get(m.id));
});

test('no expense spends nothing, and a stranger is refused', () => {
  const s = spending(members, []);
  expect([s.spentCents, ...s.paid.values(), ...s.share.values()].every((v) => v === 0)).toBe(true);
  expect(() => spending(members, [e('e1', 100, 'z', ['a'])])).toThrow(SplitError);
});
