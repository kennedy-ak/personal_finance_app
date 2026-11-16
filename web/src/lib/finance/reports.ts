/**
 * Report arithmetic from reports/presentation/reports_screen.dart, kept pure
 * so it can be tested. Every figure excludes transfers (isRealMoneyMovement).
 */

import { addDays, isBefore, makeDate, type DateOnly } from '../dates';
import { type Txn } from '../domain/transaction';
import { formatMoney, monthShort } from '../format';

export interface Stats {
  income: number;
  expense: number;
  count: number;
}

/** Monday of the week containing `d` (weeks start on Monday). */
export function weekStart(d: DateOnly): DateOnly {
  const dow = (d.getUTCDay() + 6) % 7; // Mon=0 … Sun=6
  return addDays(d, -dow);
}

export function statsBetween(txns: Txn[], from: DateOnly, to: DateOnly): Stats {
  let income = 0,
    expense = 0,
    count = 0;
  for (const t of txns) {
    if (!t.isRealMoneyMovement) continue;
    if (isBefore(t.date, from) || !isBefore(t.date, to)) continue;
    count++;
    if (t.type === 'Income') income += t.amount;
    else if (t.type === 'Expense') expense += t.amount;
  }
  return { income, expense, count };
}

/** Spending per day Mon–Sun for the week starting `monday`. */
export function dailySpend(txns: Txn[], monday: DateOnly): number[] {
  const days = [0, 0, 0, 0, 0, 0, 0];
  const end = addDays(monday, 7);
  for (const t of txns) {
    if (!t.isSpending || isBefore(t.date, monday) || !isBefore(t.date, end)) continue;
    days[Math.round((t.date.getTime() - monday.getTime()) / 86_400_000)] += t.amount;
  }
  return days;
}

export interface MonthStat {
  month: DateOnly;
  income: number;
  expense: number;
  net: number;
}

/** The last six calendar months, oldest first, ending with the month of `now`. */
export function lastSixMonths(txns: Txn[], now: DateOnly): MonthStat[] {
  const out: MonthStat[] = [];
  for (let back = 5; back >= 0; back--) {
    const from = makeDate(now.getUTCFullYear(), now.getUTCMonth() + 1 - back, 1);
    const to = makeDate(from.getUTCFullYear(), from.getUTCMonth() + 2, 1);
    const s = statsBetween(txns, from, to);
    out.push({ month: from, income: s.income, expense: s.expense, net: s.income - s.expense });
  }
  return out;
}

/** The "Reading" sentence: arithmetic, not judgement. */
export function reading(months: MonthStat[]): string {
  const current = months[months.length - 1];
  if (months.every((m) => m.income === 0 && m.expense === 0)) {
    return 'Nothing logged in the last six months yet. Once a couple of months are in, this reads the shape of them for you.';
  }
  const negatives = months.filter((m) => m.net < 0).length;
  if (negatives === 0) {
    return `Every one of the last six months ended positive. ${monthShort(current.month)} is running at ${formatMoney(current.net)}.`;
  }
  const worst = months.reduce((a, b) => (b.net < a.net ? b : a));
  return (
    `${negatives} of the last six months ended negative, the deepest ${monthShort(worst.month)} at ${formatMoney(worst.net)}. ` +
    `${monthShort(current.month)} is at ${formatMoney(current.net)} so far.`
  );
}

export function byCategory(txns: Txn[], from: DateOnly, to: DateOnly) {
  const totals = new Map<string, number>();
  for (const t of txns) {
    if (!t.isSpending || isBefore(t.date, from) || !isBefore(t.date, to)) continue;
    totals.set(t.category, (totals.get(t.category) ?? 0) + t.amount);
  }
  return [...totals.entries()].map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value);
}

export function byAccount(txns: Txn[], from: DateOnly, to: DateOnly) {
  const rows = new Map<string, { inflow: number; outflow: number }>();
  for (const t of txns) {
    if (isBefore(t.date, from) || !isBefore(t.date, to)) continue;
    const row = rows.get(t.accountId) ?? { inflow: 0, outflow: 0 };
    if (t.isIncome) row.inflow += t.amount;
    else if (t.isSpending) row.outflow += t.amount;
    rows.set(t.accountId, row);
  }
  return [...rows.entries()].map(([accountId, r]) => ({ accountId, ...r, net: r.inflow - r.outflow }));
}
