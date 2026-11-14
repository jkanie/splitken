// Runs every case in spec/cases.json against the TypeScript core. The Dart
// core runs the same file (core/test/cases_test.dart).
import cases from '../../spec/cases.json';
import {
  type Expense,
  SplitError,
  balances,
  expenseFromJson,
  fold,
  formatCents,
  memberFromJson,
  opFromJson,
  parseCents,
  settleUp,
  splitExpense,
} from '../src/core';

type Case = Record<string, any>;

function code(action: () => unknown): string {
  try {
    action();
  } catch (e) {
    if (e instanceof SplitError) return e.code;
    throw e;
  }
  throw new Error('expected a SplitError');
}

const asObject = (net: Map<string, number>) => Object.fromEntries(net);

describe('split', () => {
  test.each((cases.split as Case[]).map((c) => [c.name, c]))('%s', (_, c) => {
    const expense = expenseFromJson(c.expense);
    if ('error' in c) {
      expect(code(() => splitExpense(expense))).toBe(c.error);
    } else {
      const owed = splitExpense(expense);
      expect(owed).toEqual(c.owed);
      expect(owed.reduce((a, b) => a + b, 0)).toBe(expense.amountCents);
    }
  });
});

describe('balances and settle-up', () => {
  test.each((cases.balances as Case[]).map((c) => [c.name, c]))('%s', (_, c) => {
    const members = c.members.map(memberFromJson);
    const expenses: Expense[] = c.expenses.map(expenseFromJson);
    if ('error' in c) {
      expect(code(() => balances(members, expenses))).toBe(c.error);
      return;
    }
    const net = balances(members, expenses);
    expect(asObject(net)).toEqual(c.net);
    expect([...net.keys()]).toEqual(members.map((m: { id: string }) => m.id));
    const transfers = settleUp(members, net);
    expect(transfers).toEqual(c.settle);

    // Paying the suggested transfers leaves every balance at 0.
    const paid: Expense[] = [
      ...expenses,
      ...transfers.map((t, i) => ({
        id: `settle-${i}`,
        description: 'Settle',
        amountCents: t.amountCents,
        paidBy: t.from,
        participants: [t.to],
        method: 'exact' as const,
        weights: [t.amountCents],
        isTransfer: true,
      })),
    ];
    expect(new Set(balances(members, paid).values())).toEqual(new Set([0]));
  });
});

describe('fold', () => {
  test.each((cases.fold as Case[]).map((c) => [c.name, c]))('%s', (_, c) => {
    const founders = c.founders.map(memberFromJson);
    const ops = c.ops.map(opFromJson);
    // Every rotation of the list, forwards and backwards.
    for (let k = 0; k < ops.length; k++) {
      const rotated = [...ops.slice(k), ...ops.slice(0, k)];
      for (const order of [rotated, [...rotated].reverse()]) {
        const state = fold(founders, order);
        expect(state.members).toEqual(c.members);
        expect(state.expenses.map((e) => e.id)).toEqual(c.expenseIds);
        expect(state.expenses.map((e) => e.amountCents)).toEqual(c.amounts);
        expect(asObject(balances(state.members, state.expenses))).toEqual(c.net);
      }
    }
  });
});

describe('parse and format', () => {
  test.each((cases.parse as Case[]).map((c) => [c.text, c]))('parse "%s"', (_, c) => {
    if ('error' in c) expect(code(() => parseCents(c.text))).toBe(c.error);
    else expect(parseCents(c.text)).toBe(c.cents);
  });

  test.each((cases.format as Case[]).map((c) => [c.cents, c]))('format %s', (_, c) => {
    expect(formatCents(c.cents)).toBe(c.text);
  });
});
