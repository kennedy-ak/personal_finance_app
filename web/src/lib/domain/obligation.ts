/** Mirrors lib/features/planning/domain/obligation.dart. */

import {
  addDays,
  addMonths,
  isAfter,
  isBefore,
  parseDate,
  type DateOnly,
} from '../dates';

export type Cadence = 'once' | 'weekly' | 'biweekly' | 'monthly' | 'quarterly' | 'yearly';

export const CADENCES: { value: Cadence; label: string }[] = [
  { value: 'once', label: 'One-off' },
  { value: 'weekly', label: 'Weekly' },
  { value: 'biweekly', label: 'Every 2 weeks' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'quarterly', label: 'Quarterly' },
  { value: 'yearly', label: 'Yearly' },
];

export const cadenceLabel = (c: Cadence) =>
  CADENCES.find((x) => x.value === c)?.label ?? 'Monthly';

export function cadenceFromValue(s: string | null | undefined): Cadence {
  return CADENCES.find((c) => c.value === s)?.value ?? 'monthly';
}

/** 'out' is a bill; 'in' is expected income. Stored verbatim. */
export type ObligationDirection = 'out' | 'in';

export const directionLabel = (d: ObligationDirection) =>
  d === 'out' ? 'Bill' : 'Expected income';

export class Obligation {
  constructor(
    readonly id: string,
    readonly userId: string,
    readonly name: string,
    readonly direction: ObligationDirection,
    readonly amount: number,
    readonly cadence: Cadence,
    /** The next (or only) time this lands. Recurrence rolls forward from here. */
    readonly nextDue: DateOnly,
    /** Paid from / arrives into. Null means "not decided". */
    readonly accountId: string | null,
    readonly category: string | null,
    readonly isActive: boolean,
    readonly createdAt: Date,
  ) {}

  get isOutflow(): boolean {
    return this.direction === 'out';
  }

  /**
   * Every time this obligation lands in [from, to], inclusive. Rolls an anchor
   * left in the past forward to catch up first.
   */
  occurrencesBetween(from: DateOnly, to: DateOnly): DateOnly[] {
    const start = from;
    const end = to;
    if (isBefore(end, start)) return [];

    let cursor = this.nextDue;
    const out: DateOnly[] = [];

    if (this.cadence === 'once') {
      if (!isBefore(cursor, start) && !isAfter(cursor, end)) out.push(cursor);
      return out;
    }

    let guard = 0;
    while (isBefore(cursor, start) && guard++ < 1200) {
      cursor = this.advance(cursor);
    }

    guard = 0;
    while (!isAfter(cursor, end) && guard++ < 1200) {
      out.push(cursor);
      cursor = this.advance(cursor);
    }
    return out;
  }

  /** Total landing in [from, to], as a positive number. */
  amountDueBetween(from: DateOnly, to: DateOnly): number {
    return this.occurrencesBetween(from, to).length * this.amount;
  }

  /** The first time this lands on or after `from`, if ever. */
  nextOccurrenceOnOrAfter(from: DateOnly): DateOnly | null {
    const hits = this.occurrencesBetween(from, addDays(from, 400));
    return hits.length === 0 ? null : hits[0];
  }

  private advance(d: DateOnly): DateOnly {
    switch (this.cadence) {
      case 'once':
        return addDays(d, 36500);
      case 'weekly':
        return addDays(d, 7);
      case 'biweekly':
        return addDays(d, 14);
      case 'monthly':
        return addMonths(d, 1);
      case 'quarterly':
        return addMonths(d, 3);
      case 'yearly':
        return addMonths(d, 12);
    }
  }

  static fromRow(j: Record<string, unknown>): Obligation {
    return new Obligation(
      String(j.id),
      String(j.user_id),
      String(j.name),
      j.direction === 'in' ? 'in' : 'out',
      Number(j.amount),
      cadenceFromValue(j.cadence as string | null),
      parseDate(String(j.next_due)),
      (j.account_id as string | null) ?? null,
      (j.category as string | null) ?? null,
      j.is_active === undefined || j.is_active === null ? true : Boolean(j.is_active),
      new Date(String(j.created_at)),
    );
  }
}
