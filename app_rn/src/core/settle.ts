import type { Member } from './model';

/** 1 payment that settles part of the group's balances. */
export interface Transfer {
  from: string;
  to: string;
  amountCents: number;
}

/**
 * Payments that bring every balance to 0. Each step, the member who owes the
 * most pays the member owed the most, as much as settles 1 of them. Equal
 * amounts go to the member listed 1st.
 */
export function settleUp(members: readonly Member[], net: ReadonlyMap<string, number>): Transfer[] {
  const order = new Map(members.map((m, i) => [m.id, i]));
  const owedTo = new Map<string, number>();
  const owes = new Map<string, number>();
  for (const [id, cents] of net) {
    if (cents > 0) owedTo.set(id, cents);
    if (cents < 0) owes.set(id, -cents);
  }
  const largest = (side: Map<string, number>) =>
    [...side.keys()].sort(
      (a, b) => side.get(b)! - side.get(a)! || order.get(a)! - order.get(b)!,
    )[0];

  const transfers: Transfer[] = [];
  while (owedTo.size > 0 && owes.size > 0) {
    const to = largest(owedTo);
    const from = largest(owes);
    const cents = Math.min(owedTo.get(to)!, owes.get(from)!);
    transfers.push({ from, to, amountCents: cents });
    owedTo.set(to, owedTo.get(to)! - cents);
    owes.set(from, owes.get(from)! - cents);
    if (owedTo.get(to) === 0) owedTo.delete(to);
    if (owes.get(from) === 0) owes.delete(from);
  }
  return transfers;
}
