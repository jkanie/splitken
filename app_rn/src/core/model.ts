import { SplitError } from './errors';
import { checkAmount } from './money';

export type SplitMethod = 'equal' | 'exact' | 'shares' | 'percent';

export const splitMethods: readonly SplitMethod[] = ['equal', 'exact', 'shares', 'percent'];

export interface Member {
  id: string;
  name: string;
}

/**
 * An expense, or a transfer when `isTransfer` is true: `paidBy` paid
 * `amountCents`, and `participants` each owe their part of it.
 *
 * `weights` holds 1 number per participant: cents for `exact`, shares for
 * `shares`, basis points for `percent`. It is empty for `equal`.
 */
export interface Expense {
  id: string;
  description: string;
  amountCents: number;
  paidBy: string;
  participants: string[];
  method: SplitMethod;
  weights: number[];
  isTransfer: boolean;
}

type Json = Record<string, unknown>;

export function isJsonObject(value: unknown): value is Json {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function memberFromJson(json: unknown): Member {
  if (!isJsonObject(json) || typeof json.id !== 'string' || typeof json.name !== 'string') {
    throw new SplitError('bad_member', 'A member has a string id and name.');
  }
  return { id: json.id, name: json.name };
}

/** Reads an expense as the API and spec/cases.json write it. */
export function expenseFromJson(json: unknown): Expense {
  if (!isJsonObject(json)) {
    throw new SplitError('bad_expense', 'An expense is a JSON object.');
  }
  const field = <T>(name: string, ok: (v: unknown) => v is T): T => {
    const value = json[name];
    if (!ok(value)) {
      throw new SplitError(
        'bad_expense',
        `The expense field "${name}" is missing or of the wrong type.`,
      );
    }
    return value;
  };
  const isString = (v: unknown): v is string => typeof v === 'string';
  const isInt = (v: unknown): v is number => Number.isSafeInteger(v);
  const isList = (v: unknown): v is unknown[] => Array.isArray(v);

  const methodName = json.method ?? 'equal';
  const method = splitMethods.find((m) => m === methodName);
  if (method === undefined) {
    throw new SplitError('bad_expense', `Unknown split method "${String(methodName)}".`);
  }
  const weights = json.weights ?? [];
  if (!isList(weights)) {
    throw new SplitError('bad_expense', 'weights is a list.');
  }
  return {
    id: field('id', isString),
    description: field('description', isString),
    amountCents: field('amountCents', isInt),
    paidBy: field('paidBy', isString),
    participants: field('participants', isList).map((p) => {
      if (typeof p !== 'string') {
        throw new SplitError('bad_expense', 'A participant must be a member id.');
      }
      return p;
    }),
    method,
    weights: weights.map((w) => {
      if (!isInt(w)) {
        throw new SplitError('bad_expense', 'A weight must be a whole number.');
      }
      return w;
    }),
    isTransfer: json.isTransfer === true,
  };
}

/** Checks an expense against the group's members. splitExpense checks the split. */
export function validateExpense(e: Expense, memberIds: ReadonlySet<string>): void {
  if (e.id.length === 0 || e.id.length > 64) {
    throw new SplitError('bad_expense', 'An expense id is 1 to 64 characters.');
  }
  if (e.description.trim().length === 0 || e.description.length > 200) {
    throw new SplitError('bad_expense', 'A description is 1 to 200 characters.');
  }
  checkAmount(e.amountCents);
  if (!memberIds.has(e.paidBy)) {
    throw new SplitError('unknown_member', `The payer "${e.paidBy}" is not in the group.`);
  }
  if (e.participants.length === 0) {
    throw new SplitError('bad_expense', 'An expense needs at least 1 participant.');
  }
  if (new Set(e.participants).size !== e.participants.length) {
    throw new SplitError('bad_expense', 'A participant is listed twice.');
  }
  for (const p of e.participants) {
    if (!memberIds.has(p)) {
      throw new SplitError('unknown_member', `The participant "${p}" is not in the group.`);
    }
  }
  if (e.isTransfer) {
    if (e.participants.length !== 1 || e.participants[0] === e.paidBy) {
      throw new SplitError('bad_transfer', 'A transfer goes from 1 member to 1 other member.');
    }
    if (e.method !== 'exact' || e.weights.length !== 1 || e.weights[0] !== e.amountCents) {
      throw new SplitError(
        'bad_transfer',
        'A transfer has the method exact and 1 weight equal to its amount.',
      );
    }
  }
}
