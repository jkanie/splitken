import { SplitError } from './errors';

/**
 * The largest amount 1 expense may hold, in cents: 10 million in the group's
 * currency. Every sum stays well inside Number.MAX_SAFE_INTEGER.
 */
export const maxAmountCents = 1_000_000_000;

/** Reads a typed amount such as `12`, `12.5` or `12.50` into cents. */
export function parseCents(text: string): number {
  const match = /^(\d{1,8})(?:\.(\d{1,2}))?$/.exec(text.trim());
  if (match == null) {
    throw new SplitError('bad_amount', 'Type an amount such as 12 or 12.50.');
  }
  const cents = Number(match[1]) * 100 + Number((match[2] ?? '').padEnd(2, '0'));
  checkAmount(cents);
  return cents;
}

/** Refuses an amount of 0 or less, or above maxAmountCents. */
export function checkAmount(cents: number): void {
  if (!Number.isSafeInteger(cents) || cents <= 0 || cents > maxAmountCents) {
    throw new SplitError(
      'bad_amount',
      `An amount must be above 0 and at most ${formatCents(maxAmountCents)}.`,
    );
  }
}

/** Writes cents with 2 decimals and no grouping: 123456 -> `1234.56`. */
export function formatCents(cents: number): string {
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  const whole = Math.floor(abs / 100);
  const fraction = String(abs % 100).padStart(2, '0');
  return `${sign}${whole}.${fraction}`;
}
