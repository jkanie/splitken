import { SplitError } from './errors';
import type { Expense } from './model';

/** The most shares 1 expense may hand out in total. */
export const maxTotalShares = 1_000_000;

const sum = (xs: readonly number[]) => xs.reduce((a, b) => a + b, 0);

/**
 * What each participant owes for an expense, in cents, in the order of
 * `participants`. The parts always add up to the amount. The rules match
 * the Dart core exactly, which spec/cases.json checks on both sides.
 */
export function splitExpense(expense: Expense): number[] {
  const n = expense.participants.length;
  const amount = expense.amountCents;
  if (n === 0) {
    throw new SplitError('bad_expense', 'An expense needs at least 1 participant.');
  }
  const w = expense.weights;
  switch (expense.method) {
    case 'equal':
      if (w.length > 0) throw new SplitError('bad_split', 'An equal split takes no weights.');
      return largestRemainder(amount, new Array<number>(n).fill(1));
    case 'exact': {
      checkCount(expense);
      if (w.some((x) => x < 0)) {
        throw new SplitError('bad_split', 'An exact part may not be below 0.');
      }
      const total = sum(w);
      if (total !== amount) {
        throw new SplitError(
          'bad_split',
          `The exact parts add up to ${total} cents, not ${amount}.`,
        );
      }
      return [...w];
    }
    case 'shares': {
      checkCount(expense);
      if (w.some((x) => x < 1)) {
        throw new SplitError('bad_split', 'Each share is a whole number of 1 or more.');
      }
      if (sum(w) > maxTotalShares) {
        throw new SplitError('bad_split', `The shares add up to more than ${maxTotalShares}.`);
      }
      return largestRemainder(amount, w);
    }
    case 'percent': {
      checkCount(expense);
      if (w.some((x) => x < 0)) {
        throw new SplitError('bad_split', 'A percentage may not be below 0.');
      }
      const total = sum(w);
      if (total !== 10000) {
        throw new SplitError('bad_split', `The percentages add up to ${total / 100}%, not 100%.`);
      }
      return largestRemainder(amount, w);
    }
  }
}

function checkCount(expense: Expense): void {
  if (expense.weights.length !== expense.participants.length) {
    throw new SplitError('bad_split', 'Give 1 weight per participant.');
  }
}

/**
 * Integer division of 2 safe integers. A float divide can round up to the
 * next whole number near a boundary, so the remainder corrects it.
 */
function divMod(a: number, b: number): [number, number] {
  let q = Math.floor(a / b);
  let r = a - q * b;
  if (r < 0) {
    q -= 1;
    r += b;
  } else if (r >= b) {
    q += 1;
    r -= b;
  }
  return [q, r];
}

function largestRemainder(amount: number, weights: readonly number[]): number[] {
  const total = sum(weights);
  const parts: number[] = [];
  const remainders: number[] = [];
  for (const w of weights) {
    const [q, r] = divMod(amount * w, total);
    parts.push(q);
    remainders.push(r);
  }
  let left = amount - sum(parts);
  const order = weights.map((_, i) => i).sort((a, b) => remainders[b] - remainders[a] || a - b);
  for (const i of order) {
    if (left === 0) break;
    parts[i] += 1;
    left -= 1;
  }
  return parts;
}
