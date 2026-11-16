import { type Expense, splitExpense } from '../src/core';
import { OfflineError, RefusedError, groupTotalsFromJson } from '../src/api';
import { Library } from '../src/library';
import { MemoryStore } from '../src/storage';
import { FakeServer } from './fakeServer';

const expense = (id: string, cents: number, paidBy: string, participants: string[]): Expense => ({
  id,
  description: id,
  amountCents: cents,
  paidBy,
  participants,
  method: 'equal',
  weights: [],
  isTransfer: false,
});

test('totals gives what the group spent and what each member paid and owes', async () => {
  const server = new FakeServer();
  const book = await (
    await Library.load(server.client(), new MemoryStore())
  ).create('Trip', 'CAD', ['Ana', 'Ben', 'Cy']);
  const dinner = expense('e1', 1000, 'm1', ['m1', 'm2', 'm3']);
  const taxi = expense('e2', 600, 'm2', ['m2', 'm3']);
  await book.saveExpense(dinner);
  await book.saveExpense(taxi);
  // A transfer that settles up is not spending.
  await book.recordTransfer(book.settle[0]);
  expect(await book.sync()).toBe(true);

  const totals = await server.client().totals(book.meta.id);
  expect(totals.currency).toBe('CAD');
  expect(totals.spentCents).toBe(1600);
  expect(totals.members.map((m) => m.name)).toEqual(['Ana', 'Ben', 'Cy']);
  expect(totals.members.map((m) => m.paidCents)).toEqual([1000, 600, 0]);
  // Each share is the expense split as the app splits it, so the 1 cent left over is counted once.
  const d = splitExpense(dinner);
  const t = splitExpense(taxi);
  expect(totals.members.map((m) => m.shareCents)).toEqual([d[0], d[1] + t[0], d[2] + t[1]]);
});

test('totals of a group that does not exist is refused, and offline says so', async () => {
  const server = new FakeServer();
  await expect(server.client().totals('nope')).rejects.toBeInstanceOf(RefusedError);
  server.online = false;
  await expect(server.client().totals('nope')).rejects.toBeInstanceOf(OfflineError);
});

test('totals in a form the app does not know is an OfflineError', () => {
  expect(() => groupTotalsFromJson({ currency: 'CAD', spent: 1.5, members: [] })).toThrow(
    OfflineError,
  );
  expect(() =>
    groupTotalsFromJson({
      currency: 'CAD',
      spent: 0,
      members: [{ id: 'm1', name: 'Ana', paid: 0 }],
    }),
  ).toThrow(OfflineError);
  expect(groupTotalsFromJson({ currency: 'CAD', spent: 0, members: [] })).toEqual({
    currency: 'CAD',
    spentCents: 0,
    members: [],
  });
});
