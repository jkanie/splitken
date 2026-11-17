import {
  type Expense,
  type GroupState,
  type Member,
  type Op,
  type OpKind,
  type Spending,
  SplitError,
  type Transfer,
  balances,
  fold,
  nextLamport,
  opFromJson,
  opToJson,
  settleUp,
  spending,
  splitExpense,
  validateExpense,
} from './core';
import { type ApiClient, type GroupMeta, OfflineError, RefusedError, type SyncResult } from './api';
import { randomId } from './ids';
import type { KeyValueStore } from './storage';

/**
 * 1 group on this device: the operations the server has confirmed, the ones
 * made here and not sent yet, the state both fold into. The same design as
 * the Flutter app's GroupBook, with subscribe() in place of ChangeNotifier.
 */
export class GroupBook {
  readonly confirmed: Op[];
  readonly pending: Op[];
  seq: number;
  syncing = false;
  lastProblem: string | null = null;
  state!: GroupState;
  net!: Map<string, number>;

  private readonly listeners = new Set<() => void>();
  private version = 0;

  constructor(
    readonly meta: GroupMeta,
    readonly clientId: string,
    private readonly api: ApiClient,
    private readonly store: KeyValueStore,
    saved: { confirmed?: Op[]; pending?: Op[]; seq?: number } = {},
  ) {
    this.confirmed = saved.confirmed ?? [];
    this.pending = saved.pending ?? [];
    this.seq = saved.seq ?? 0;
    this.refold();
  }

  static storageKey(groupId: string) {
    return `group:${groupId}`;
  }

  /** For useSyncExternalStore. */
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getVersion = () => this.version;

  get settle(): Transfer[] {
    return settleUp(this.state.members, this.net);
  }

  /** What the group spent and each member's part of it, pending changes included, from the core's spending. */
  get spent(): Spending {
    return spending(this.state.members, this.state.expenses);
  }

  memberName(id: string): string {
    return this.state.members.find((m) => m.id === id)?.name ?? id;
  }

  /** The line under a member on the Members tab: how many expenses they paid, settle-up payments left out. */
  paidCountLine(memberId: string): string {
    const n = this.state.expenses.filter((e) => !e.isTransfer && e.paidBy === memberId).length;
    if (n === 0) return 'No expenses paid yet';
    return n === 1 ? 'Paid for 1 expense' : `Paid for ${n} expenses`;
  }

  /**
   * The line under an expense in the list: who paid and how it is split, such as "Ana paid, split 3 ways by shares".
   * A settle-up payment names itself, since its description already says who paid whom.
   */
  paidLine(e: Expense): string {
    if (e.isTransfer) return 'Settle-up payment';
    const payer = `${this.memberName(e.paidBy)} paid`;
    if (e.participants.length === 1)
      return `${payer}, for ${this.memberName(e.participants[0])} only`;
    const by = {
      equal: '',
      exact: ' by exact amounts',
      shares: ' by shares',
      percent: ' by percent',
    }[e.method];
    return `${payer}, split ${e.participants.length} ways${by}`;
  }

  private notify() {
    this.version++;
    for (const l of this.listeners) l();
  }

  private refold() {
    this.state = fold(this.meta.founders, [...this.confirmed, ...this.pending]);
    this.net = balances(this.state.members, this.state.expenses);
  }

  private op(kind: OpKind, fields: Partial<Op>): Op {
    return {
      opId: randomId(),
      clientId: this.clientId,
      lamport: nextLamport([...this.confirmed, ...this.pending]),
      kind,
      ...fields,
    };
  }

  /** Adds an expense, or replaces the 1 with the same id. Throws a SplitError when it breaks a rule. */
  async saveExpense(expense: Expense): Promise<void> {
    validateExpense(expense, new Set(this.state.members.map((m) => m.id)));
    splitExpense(expense);
    await this.add(this.op('expense', { expense }));
  }

  deleteExpense(expenseId: string): Promise<void> {
    return this.add(this.op('delete', { expenseId }));
  }

  /** Adds a member with an id that starts with this device's client id. */
  async addMember(name: string): Promise<Member> {
    const trimmed = name.trim();
    if (trimmed.length === 0 || trimmed.length > 60) {
      throw new SplitError('bad_member', 'A name is 1 to 60 characters.');
    }
    // As the server refuses for founders: Ana and ana are 1 name.
    if (this.state.members.some((m) => m.name.toLowerCase() === trimmed.toLowerCase())) {
      throw new SplitError('bad_member', `"${trimmed}" is already a member.`);
    }
    const member = { id: `${this.clientId}-${randomId(6)}`, name: trimmed };
    await this.add(this.op('member', { member }));
    return member;
  }

  recordTransfer(t: Transfer): Promise<void> {
    return this.saveExpense({
      id: randomId(),
      description: `${this.memberName(t.from)} paid ${this.memberName(t.to)}`,
      amountCents: t.amountCents,
      paidBy: t.from,
      participants: [t.to],
      method: 'exact',
      weights: [t.amountCents],
      isTransfer: true,
    });
  }

  private async add(op: Op) {
    this.pending.push(op);
    this.refold();
    await this.save();
    this.notify();
  }

  /**
   * Sends the pending operations and takes in everyone else's. With no
   * network they stay for the next try. An operation the server refuses is
   * dropped, since it would be refused every time.
   */
  async sync(): Promise<boolean> {
    if (this.syncing) return false;
    this.syncing = true;
    this.lastProblem = null;
    this.notify();
    try {
      for (let attempt = 0; attempt < 3; attempt++) {
        const sending = [...this.pending];
        try {
          this.take(await this.api.sync(this.meta.id, this.seq, sending), sending);
          return true;
        } catch (e) {
          if (!(e instanceof RefusedError)) throw e;
          if (e.code === 'seq_ahead') {
            // The server has less than this device saw, such as after a restore from an older back-up. Send
            // everything again from 0: the server keeps what it has once and takes the rest.
            const again = this.confirmed.map(({ seq: _seq, ...op }) => op);
            this.pending.splice(0, 0, ...again);
            this.confirmed.splice(0, this.confirmed.length);
            this.seq = 0;
            continue;
          }
          const refused = this.pending.findIndex((op) => op.opId === e.opId);
          if (refused < 0) {
            this.lastProblem = e.message;
            return false;
          }
          this.pending.splice(refused, 1);
          this.lastProblem = `A change was refused and removed: ${e.message}`;
        }
      }
      return false;
    } catch (e) {
      if (!(e instanceof OfflineError)) throw e;
      this.lastProblem = 'Offline. Changes are kept here and sent later.';
      return false;
    } finally {
      this.syncing = false;
      this.refold();
      await this.save();
      this.notify();
    }
  }

  private take(result: SyncResult, sent: Op[]) {
    const known = new Set(this.confirmed.map((op) => `${op.clientId}\u0000${op.opId}`));
    for (const op of result.ops) {
      const key = `${op.clientId}\u0000${op.opId}`;
      if (!known.has(key)) {
        known.add(key);
        this.confirmed.push(op);
      }
    }
    const sentIds = new Set(sent.map((op) => op.opId));
    const keep = this.pending.filter((op) => !sentIds.has(op.opId));
    this.pending.splice(0, this.pending.length, ...keep);
    this.seq = result.seq;
  }

  save(): Promise<void> {
    return this.store.write(
      GroupBook.storageKey(this.meta.id),
      JSON.stringify({
        meta: this.meta,
        seq: this.seq,
        confirmed: this.confirmed.map((op) => ({ ...opToJson(op), seq: op.seq })),
        pending: this.pending.map(opToJson),
      }),
    );
  }

  static fromJson(json: string, clientId: string, api: ApiClient, store: KeyValueStore): GroupBook {
    const saved = JSON.parse(json) as {
      meta: GroupMeta;
      seq: number;
      confirmed: unknown[];
      pending: unknown[];
    };
    return new GroupBook(saved.meta, clientId, api, store, {
      seq: saved.seq,
      confirmed: saved.confirmed.map(opFromJson),
      pending: saved.pending.map(opFromJson),
    });
  }
}
