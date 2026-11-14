import { SplitError } from './errors';
import { type Expense, type Member, expenseFromJson, isJsonObject, memberFromJson } from './model';

export type OpKind = 'member' | 'expense' | 'delete';

/**
 * 1 change made on 1 device. Between 2 changes to the same member or
 * expense, the higher (lamport, clientId, opId) wins. `seq` is the server's
 * order of arrival, absent until the server has the operation.
 */
export interface Op {
  opId: string;
  clientId: string;
  lamport: number;
  kind: OpKind;
  member?: Member;
  expense?: Expense;
  expenseId?: string;
  seq?: number;
}

/** The highest Lamport value accepted: 2^53 - 1. */
export const maxLamport = Number.MAX_SAFE_INTEGER;

export function opTarget(op: Op): string {
  switch (op.kind) {
    case 'member':
      return op.member!.id;
    case 'expense':
      return op.expense!.id;
    case 'delete':
      return op.expenseId!;
  }
}

/** Reads and checks an operation, with the same rules as the Dart core. */
export function opFromJson(json: unknown): Op {
  if (!isJsonObject(json)) throw new SplitError('bad_op', 'An operation is a JSON object.');
  const { opId, clientId, lamport, kind, seq } = json;
  if (
    (kind !== 'member' && kind !== 'expense' && kind !== 'delete') ||
    typeof opId !== 'string' ||
    typeof clientId !== 'string' ||
    !Number.isSafeInteger(lamport)
  ) {
    throw new SplitError('bad_op', 'An operation needs opId, clientId, lamport and a known kind.');
  }
  if (opId.length === 0 || opId.length > 64 || clientId.length === 0 || clientId.length > 64) {
    throw new SplitError('bad_op', 'opId and clientId are 1 to 64 characters.');
  }
  const stamp = lamport as number;
  if (stamp < 1 || stamp > maxLamport) {
    throw new SplitError('bad_op', `lamport is from 1 to ${maxLamport}.`);
  }
  const base: Op = { opId, clientId, lamport: stamp, kind };
  if (Number.isSafeInteger(seq)) base.seq = seq as number;
  switch (kind) {
    case 'member': {
      if (!isJsonObject(json.member)) {
        throw new SplitError('bad_op', 'A member operation holds a member.');
      }
      const m = memberFromJson(json.member);
      if (
        m.id.length === 0 ||
        m.id.length > 64 ||
        m.name.trim().length === 0 ||
        m.name.length > 60
      ) {
        throw new SplitError('bad_member', 'A member id is 1 to 64 characters and a name 1 to 60.');
      }
      return { ...base, member: m };
    }
    case 'expense':
      if (!isJsonObject(json.expense)) {
        throw new SplitError('bad_op', 'An expense operation holds an expense.');
      }
      return { ...base, expense: expenseFromJson(json.expense) };
    case 'delete':
      if (typeof json.expenseId !== 'string' || json.expenseId.length === 0) {
        throw new SplitError('bad_op', 'A delete operation names an expenseId.');
      }
      return { ...base, expenseId: json.expenseId };
  }
}

/** The operation as a device sends it, without the server's seq. */
export function opToJson(op: Op): Record<string, unknown> {
  const { seq: _seq, ...rest } = op;
  return rest;
}

/**
 * Orders 2 operations: the later one wins. Strings compare by UTF-16 code
 * unit, as Dart's String.compareTo does, never by locale.
 */
export function compareStamps(a: Op, b: Op): number {
  if (a.lamport !== b.lamport) return a.lamport < b.lamport ? -1 : 1;
  if (a.clientId !== b.clientId) return a.clientId < b.clientId ? -1 : 1;
  if (a.opId !== b.opId) return a.opId < b.opId ? -1 : 1;
  return 0;
}

export interface GroupState {
  members: Member[];
  expenses: Expense[];
}

/**
 * Folds operations into a group that starts with `founders`. The result is
 * the same for any order, and an operation sent twice counts once.
 */
export function fold(founders: readonly Member[], ops: Iterable<Op>): GroupState {
  const unique = new Map<string, Op>();
  for (const op of ops) unique.set(`${op.clientId}\u0000${op.opId}`, op);
  const sorted = [...unique.values()].sort(compareStamps);

  const names = new Map(founders.map((m) => [m.id, m.name]));
  const memberOrder = founders.map((m) => m.id);
  const latest = new Map<string, Op>();
  const expenseOrder: string[] = [];
  for (const op of sorted) {
    if (op.kind === 'member') {
      if (!names.has(op.member!.id)) memberOrder.push(op.member!.id);
      names.set(op.member!.id, op.member!.name);
    } else {
      const target = opTarget(op);
      if (!latest.has(target)) expenseOrder.push(target);
      latest.set(target, op);
    }
  }
  return {
    members: memberOrder.map((id) => ({ id, name: names.get(id)! })),
    expenses: expenseOrder
      .map((id) => latest.get(id)!)
      .filter((op) => op.kind === 'expense')
      .map((op) => op.expense!),
  };
}

/** The Lamport value for a new operation on a device that has seen `ops`. */
export function nextLamport(ops: Iterable<Op>): number {
  let high = 0;
  for (const op of ops) if (op.lamport > high) high = op.lamport;
  return high + 1;
}
