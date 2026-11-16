import { describe, expect, it } from 'vitest';
import { makeDate } from '@/lib/dates';
import { txn } from '@/test/fixtures';
import { byAccount, byCategory, dailySpend, lastSixMonths, reading, statsBetween, weekStart } from './reports';

// 2026-07-15 is a Wednesday.
const wed = makeDate(2026, 7, 15);

describe('reports', () => {
  it('weeks start on Monday', () => {
    expect(weekStart(wed)).toEqual(makeDate(2026, 7, 13));
    expect(weekStart(makeDate(2026, 7, 19))).toEqual(makeDate(2026, 7, 13)); // Sunday
    expect(weekStart(makeDate(2026, 7, 13))).toEqual(makeDate(2026, 7, 13));
  });

  const txns = [
    txn({ account: 'a', type: 'Expense', amount: 40, date: makeDate(2026, 7, 13) }),
    txn({ account: 'a', type: 'Expense', amount: 60, date: makeDate(2026, 7, 15), category: 'Transportation' }),
    txn({ account: 'a', type: 'Income', amount: 500, date: makeDate(2026, 7, 14), category: 'Salary' }),
    txn({ account: 'a', to: 'b', type: 'Transfer', amount: 900, date: makeDate(2026, 7, 14), category: 'Transfer' }),
    txn({ account: 'a', type: 'Expense', amount: 1000, date: makeDate(2026, 6, 10) }),
  ];

  it('transfers never count as income or spending', () => {
    const s = statsBetween(txns, makeDate(2026, 7, 13), makeDate(2026, 7, 20));
    expect(s).toEqual({ income: 500, expense: 100, count: 3 });
  });

  it('daily spend lands on the right weekday', () => {
    expect(dailySpend(txns, makeDate(2026, 7, 13))).toEqual([40, 0, 60, 0, 0, 0, 0]);
  });

  it('six months end with the current one, and the reading names the worst', () => {
    const months = lastSixMonths(txns, wed);
    expect(months).toHaveLength(6);
    expect(months.at(-1)!.month).toEqual(makeDate(2026, 7, 1));
    expect(months.at(-1)!.net).toBe(400);
    expect(months.at(-2)!.net).toBe(-1000);
    expect(reading(months)).toBe(
      '1 of the last six months ended negative, the deepest Jun at -GHS 1,000.00. Jul is at GHS 400.00 so far.',
    );
  });

  it('reading copes with an empty history', () => {
    expect(reading(lastSixMonths([], wed))).toMatch(/^Nothing logged/);
  });

  it('category and account breakdowns for a week', () => {
    const from = makeDate(2026, 7, 13);
    const to = makeDate(2026, 7, 20);
    expect(byCategory(txns, from, to)).toEqual([
      { name: 'Transportation', value: 60 },
      { name: 'Food & Dining', value: 40 },
    ]);
    expect(byAccount(txns, from, to)).toEqual([{ accountId: 'a', inflow: 500, outflow: 100, net: 400 }]);
  });
});
