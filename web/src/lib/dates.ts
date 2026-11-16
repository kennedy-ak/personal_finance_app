/**
 * Calendar dates, without time zones getting a vote.
 *
 * The Dart app uses local-midnight `DateTime`s for everything date-shaped
 * (transaction dates, due dates, "today"). JavaScript `Date`s carry a zone and
 * DST, which makes "how many days apart" quietly wrong twice a year. So a
 * calendar date here is a `Date` pinned to **UTC midnight**, and every helper
 * below works in UTC. Day arithmetic is then exact.
 */

const MS_PER_DAY = 86_400_000;

/** A calendar date at UTC midnight. */
export type DateOnly = Date;

export function makeDate(year: number, month: number, day: number): DateOnly {
  return new Date(Date.UTC(year, month - 1, day));
}

/** Today in the viewer's own calendar, as a UTC-midnight date. */
export function today(now: Date = new Date()): DateOnly {
  return makeDate(now.getFullYear(), now.getMonth() + 1, now.getDate());
}

/**
 * Parses `YYYY-MM-DD` (a Postgres `date`) or the date part of an ISO string.
 * Dart writes `next_due` on coach actions as `2026-08-28T00:00:00.000`, so the
 * time part is ignored rather than shifted through a zone.
 */
export function parseDate(s: string): DateOnly {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s.trim());
  if (!m) throw new Error(`Not a date: ${s}`);
  return makeDate(Number(m[1]), Number(m[2]), Number(m[3]));
}

export function tryParseDate(s: string | null | undefined): DateOnly | null {
  if (!s) return null;
  try {
    const d = parseDate(s);
    // Reject impossible dates like 2026-02-31, which Date.UTC would roll over.
    return toIsoDate(d) === s.trim().slice(0, 10) ? d : null;
  } catch {
    return null;
  }
}

/** `YYYY-MM-DD`, the form Postgres `date` columns take. */
export function toIsoDate(d: DateOnly): string {
  return d.toISOString().slice(0, 10);
}

export function addDays(d: DateOnly, days: number): DateOnly {
  return new Date(d.getTime() + days * MS_PER_DAY);
}

/** Whole days from `from` to `to` (positive when `to` is later). */
export function diffDays(to: DateOnly, from: DateOnly): number {
  return Math.round((to.getTime() - from.getTime()) / MS_PER_DAY);
}

/**
 * Adds months, clamping the day to the target month's length so the 31st of
 * January lands on the 28th/29th of February rather than overflowing to March.
 */
export function addMonths(d: DateOnly, months: number): DateOnly {
  const total = d.getUTCMonth() + months;
  const year = d.getUTCFullYear() + Math.floor(total / 12);
  const month = ((total % 12) + 12) % 12; // 0-based
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const day = Math.min(d.getUTCDate(), lastDay);
  // Matches Dart's `d.day < lastDay ? d.day : lastDay`.
  return new Date(Date.UTC(year, month, day));
}

export const isBefore = (a: DateOnly, b: DateOnly) => a.getTime() < b.getTime();
export const isAfter = (a: DateOnly, b: DateOnly) => a.getTime() > b.getTime();
export const sameDay = (a: DateOnly, b: DateOnly) => a.getTime() === b.getTime();
