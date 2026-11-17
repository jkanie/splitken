import { type Expense, SplitError } from '../src/core';
import { GroupBook } from '../src/groupBook';
import { Library } from '../src/library';
import { MemoryStore } from '../src/storage';
import { FakeServer } from './fakeServer';

const dinner = (id: string, cents: number, paidBy = 'm1'): Expense => ({
  id,
  description: 'Dinner',
  amountCents: cents,
  paidBy,
  participants: ['m1', 'm2', 'm3'],
  method: 'equal',
  weights: [],
  isTransfer: false,
});

let server: FakeServer;
beforeEach(() => {
  server = new FakeServer();
});
const device = (store = new MemoryStore()) => Library.load(server.client(), store);
const net = (book: GroupBook) => Object.fromEntries(book.net);

test('an expense made offline is kept and sent on the next sync', async () => {
  const book = await (await device()).create('Trip', 'CAD', ['Ana', 'Ben', 'Cy']);
  server.online = false;
  await book.saveExpense(dinner('e1', 1000));
  expect(net(book)).toEqual({ m1: 666, m2: -333, m3: -333 });
  expect(await book.sync()).toBe(false);
  expect(book.pending).toHaveLength(1);
  expect(book.lastProblem).toMatch(/^Offline/);

  server.online = true;
  expect(await book.sync()).toBe(true);
  expect(book.pending).toHaveLength(0);
  expect(book.confirmed).toHaveLength(1);
  expect(book.seq).toBe(1);
  expect(book.lastProblem).toBeNull();
});

test('2 devices that edit the same expense offline end up the same', async () => {
  const a = await device();
  const b = await device();
  const onA = await a.create('Flat', 'EUR', ['Ana', 'Ben', 'Cy']);
  const onB = await b.join(onA.meta.id);
  await onA.saveExpense(dinner('e1', 900));
  await onA.sync();
  await onB.sync();
  expect(onB.state.expenses[0].amountCents).toBe(900);

  server.online = false;
  await onA.saveExpense(dinner('e1', 1200));
  await onB.saveExpense(dinner('e1', 1500, 'm2'));
  await onB.addMember('Di');
  server.online = true;
  await onA.sync();
  await onB.sync();
  await onA.sync();

  expect(onA.pending).toHaveLength(0);
  expect(onB.pending).toHaveLength(0);
  expect(net(onA)).toEqual(net(onB));
  expect(onA.state.members.map((m) => m.name)).toEqual(['Ana', 'Ben', 'Cy', 'Di']);
  expect(onA.state.expenses[0].amountCents).toBe(onB.state.expenses[0].amountCents);
});

test('settling up records a transfer that clears the balances', async () => {
  const book = await (await device()).create('Lunch', 'CAD', ['Ana', 'Ben', 'Cy']);
  await book.saveExpense(dinner('e1', 1000));
  expect(book.settle).toEqual([
    { from: 'm2', to: 'm1', amountCents: 333 },
    { from: 'm3', to: 'm1', amountCents: 333 },
  ]);
  for (const t of book.settle) await book.recordTransfer(t);
  expect(book.settle).toEqual([]);
  expect(new Set(book.net.values())).toEqual(new Set([0]));
  expect(await book.sync()).toBe(true);
});

test('paidLine says who paid and how the expense is split', async () => {
  const book = await (await device()).create('Lunch', 'CAD', ['Ana', 'Ben', 'Cy']);
  expect(book.paidLine(dinner('e1', 1000))).toBe('Ana paid, split 3 ways');
  const taxi = (method: Expense['method'], participants: string[]): Expense => ({
    ...dinner('e2', 900, 'm2'),
    description: 'Taxi',
    participants,
    method,
    weights: participants.map(() => 1),
  });
  expect(book.paidLine(taxi('exact', ['m1', 'm2']))).toBe(
    'Ben paid, split 2 ways by exact amounts',
  );
  expect(book.paidLine(taxi('shares', ['m1', 'm2']))).toBe('Ben paid, split 2 ways by shares');
  expect(book.paidLine(taxi('percent', ['m1', 'm2']))).toBe('Ben paid, split 2 ways by percent');
  expect(book.paidLine(taxi('equal', ['m3']))).toBe('Ben paid, for Cy only');
  // A settle-up payment's description already says who paid whom.
  await book.saveExpense(dinner('e1', 1000));
  await book.recordTransfer(book.settle[0]);
  const transfer = book.state.expenses.at(-1)!;
  expect(transfer.isTransfer).toBe(true);
  expect(book.paidLine(transfer)).toBe('Settle-up payment');
});

test('paidCountLine counts the expenses each member paid, without settle-up payments', async () => {
  const book = await (await device()).create('Lunch', 'CAD', ['Ana', 'Ben', 'Cy']);
  expect(book.paidCountLine('m1')).toBe('No expenses paid yet');
  await book.saveExpense(dinner('e1', 1000));
  expect(book.paidCountLine('m1')).toBe('Paid for 1 expense');
  await book.saveExpense(dinner('e2', 600));
  expect(book.paidCountLine('m1')).toBe('Paid for 2 expenses');
  // A settle-up payment counts for no one, not even the member who paid it.
  const t = book.settle[0];
  await book.recordTransfer(t);
  expect(book.paidCountLine('m1')).toBe('Paid for 2 expenses');
  expect(book.paidCountLine(t.from)).toBe('No expenses paid yet');
});

test('an operation the server refuses is dropped and the rest are sent', async () => {
  const book = await (await device()).create('Club', 'CAD', ['Ana', 'Ben', 'Cy']);
  await book.saveExpense(dinner('e1', 300));
  book.pending.push({
    opId: 'bad1',
    clientId: book.clientId,
    lamport: 50,
    kind: 'member',
    member: { id: 'm9', name: 'Not a founder' },
  });
  await book.saveExpense(dinner('e2', 600));

  expect(await book.sync()).toBe(true);
  expect(book.pending).toHaveLength(0);
  expect(book.confirmed.map((op) => op.opId)).not.toContain('bad1');
  expect(book.state.expenses.map((e) => e.id)).toEqual(['e1', 'e2']);
  expect(book.lastProblem).toMatch(/^A change was refused and removed/);
});

test('a wrong expense is refused on the device and nothing changes', async () => {
  const book = await (await device()).create('Club', 'CAD', ['Ana', 'Ben']);
  const bad: Expense = {
    ...dinner('e1', 1000),
    participants: ['m1', 'm2'],
    method: 'percent',
    weights: [5000, 4000],
  };
  await expect(book.saveExpense(bad)).rejects.toBeInstanceOf(SplitError);
  expect(book.pending).toHaveLength(0);
});

test('groups and pending changes survive a restart', async () => {
  const store = new MemoryStore();
  const first = await device(store);
  const book = await first.create('Trip', 'CAD', ['Ana', 'Ben']);
  server.online = false;
  await book.saveExpense({
    ...dinner('e1', 4000, 'm2'),
    description: 'Gas',
    participants: ['m1', 'm2'],
  });

  const again = await device(store);
  expect(again.clientId).toBe(first.clientId);
  const reloaded = again.books[0];
  expect(reloaded.meta.name).toBe('Trip');
  expect(reloaded.pending).toHaveLength(1);
  expect(net(reloaded)).toEqual({ m1: -2000, m2: 2000 });
  server.online = true;
  expect(await reloaded.sync()).toBe(true);
  expect(store.values.get(GroupBook.storageKey(book.meta.id))).toContain('"pending":[]');
});

test('a member name already in the group is refused, and nothing changes', async () => {
  const book = await (await device()).create('Trip', 'CAD', ['Ana', 'Ben']);
  await expect(book.addMember(' ana ')).rejects.toMatchObject({
    code: 'bad_member',
    message: '"ana" is already a member.',
  });
  expect(book.pending).toHaveLength(0);
  const di = await book.addMember('Di');
  await expect(book.addMember('DI')).rejects.toBeInstanceOf(SplitError);
  expect(book.state.members.map((m) => m.name)).toEqual(['Ana', 'Ben', 'Di']);
  expect(di.id.startsWith(`${book.clientId}-`)).toBe(true);
  // The server refuses 2 founders with 1 name in the same way.
  await expect((await device()).create('Flat', 'CAD', ['Ana', 'ANA'])).rejects.toMatchObject({
    code: 'bad_member',
    message: '"ANA" is listed twice. Each member needs a name of their own.',
  });
});

test("a server restored from an older back-up gets the device's copy again", async () => {
  const storage = new MemoryStore();
  const book = await (await device(storage)).create('Trip', 'CAD', ['Ana', 'Ben', 'Cy']);
  await book.saveExpense(dinner('e1', 900));
  await book.saveExpense(dinner('e2', 300, 'm2'));
  expect(await book.sync()).toBe(true);
  const before = net(book);

  // The same group on a server that lost its operations, then the device again from its storage.
  const restored = new FakeServer();
  restored.restore(book.meta);
  const again = (await Library.load(restored.client(), storage)).books[0];
  expect(again.seq).toBeGreaterThan(0);
  expect(await again.sync()).toBe(true);
  expect(again.pending).toHaveLength(0);
  expect(again.confirmed.map((op) => op.expense!.id)).toEqual(['e1', 'e2']);
  expect(net(again)).toEqual(before);
  expect(again.lastProblem).toBeNull();
});

test('making a group with no network says so', async () => {
  const a = await device();
  server.online = false;
  await expect(a.create('Trip', 'CAD', ['Ana'])).rejects.toThrow();
  expect(a.books).toHaveLength(0);
});
