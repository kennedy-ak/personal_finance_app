// Parity port of test/money_engine_test.dart. Same inputs, same expectations.

import { describe, expect, it } from 'vitest';
import { addDays, makeDate } from '@/lib/dates';
import {
  acc,
  daysAgo,
  goal,
  now,
  obl,
  steadySpending,
  txn,
} from '@/test/fixtures';
import { buildSnapshot, DEFAULT_HORIZON_DAYS, MIN_HORIZON_DAYS } from './money-engine';

const salaryJul31 = () =>
  obl({ name: 'Salary', amount: 4000, nextDue: makeDate(2026, 7, 31), direction: 'in' });

describe('transfers are not spending', () => {
  it('a transfer changes no income or expense figure', () => {
    const accounts = [acc('a', 'Fidelity', 3000), acc('b', 'Cash', 500)];
    const base = steadySpending('a');
    const without = buildSnapshot({ accounts, txns: base, now });
    const with_ = buildSnapshot({
      accounts,
      txns: [
        ...base,
        txn({ account: 'a', to: 'b', type: 'Transfer', amount: 800, category: 'Transfer', date: daysAgo(2) }),
      ],
      now,
    });
    expect(with_.spend30d).toBe(without.spend30d);
    expect(with_.income30d).toBe(without.income30d);
    expect(with_.dailyBurn).toBe(without.dailyBurn);
  });

  it('a transfer never appears as a spending category', () => {
    const s = buildSnapshot({
      accounts: [acc('a', 'Fidelity', 3000), acc('b', 'Cash', 500)],
      txns: [
        txn({ account: 'a', type: 'Expense', amount: 200, date: daysAgo(3) }),
        txn({ account: 'a', to: 'b', type: 'Transfer', amount: 800, category: 'Transfer', date: daysAgo(2) }),
      ],
      now,
    });
    expect(s.categories.map((c) => c.category)).not.toContain('Transfer');
    expect(s.spend30d).toBe(200);
  });

  it('legacy faked transfers are excluded too', () => {
    const s = buildSnapshot({
      accounts: [acc('a', 'Fidelity', 3000), acc('b', 'Cash', 500)],
      txns: [
        txn({ account: 'a', type: 'Expense', amount: 200, date: daysAgo(3) }),
        txn({ account: 'a', type: 'Expense', amount: 800, category: 'Transfer', date: daysAgo(2) }),
        txn({ account: 'b', type: 'Income', amount: 800, category: 'Transfer', date: daysAgo(2) }),
      ],
      now,
    });
    expect(s.spend30d).toBe(200);
    expect(s.income30d).toBe(0);
  });
});

describe('what is actually spendable', () => {
  it('locked and reserved money is not liquid', () => {
    const s = buildSnapshot({
      accounts: [
        acc('a', 'Fidelity', 3000),
        acc('b', 'Fixed deposit', 5000, { liquidity: 'locked' }),
        acc('c', 'School fees', 900, { liquidity: 'reserved' }),
      ],
      txns: [],
      now,
    });
    expect(s.totalBalance).toBe(8900);
    expect(s.liquid).toBe(3000);
    expect(s.locked).toBe(5000);
    expect(s.reserved).toBe(900);
  });

  it('safe to spend subtracts floors, goals and bills due', () => {
    const s = buildSnapshot({
      accounts: [
        acc('fid', 'Fidelity', 3000),
        acc('cash', 'Cash', 300, { kind: 'cash', minBalance: 200 }),
        acc('momo', 'Mobile Money', 1200, { kind: 'momo' }),
      ],
      txns: [],
      obligations: [
        obl({ name: 'Rent', amount: 1200, nextDue: makeDate(2026, 7, 28), accountId: 'momo' }),
        salaryJul31(),
      ],
      goals: [goal({ name: 'Emergency fund', target: 6000, saved: 1000 })],
      now,
    });
    expect(s.liquid).toBe(4500);
    expect(s.floors).toBe(200);
    expect(s.goalReserve).toBe(1000);
    expect(s.committed).toBe(1200);
    expect(s.safeToSpend).toBe(2100);
    expect(s.daysUntilIncome).toBe(16);
  });

  it('a goal parked in a locked account is not subtracted twice', () => {
    const s = buildSnapshot({
      accounts: [
        acc('fid', 'Fidelity', 2000),
        acc('vault', 'Fixed deposit', 5000, { liquidity: 'locked' }),
      ],
      txns: [],
      goals: [goal({ name: 'House', target: 5000, saved: 5000, accountId: 'vault' })],
      now,
    });
    expect(s.goalReserve).toBe(0);
    expect(s.safeToSpend).toBe(2000);
  });

  it('archived accounts are ignored entirely', () => {
    const s = buildSnapshot({
      accounts: [acc('a', 'Fidelity', 3000), acc('old', 'Closed', 900, { archived: true })],
      txns: [],
      now,
    });
    expect(s.totalBalance).toBe(3000);
    expect(s.standings.map((x) => x.account.id)).not.toContain('old');
  });

  it('an account below its floor offers nothing to move', () => {
    const s = buildSnapshot({
      accounts: [acc('cash', 'Cash', 120, { minBalance: 300 })],
      txns: [],
      now,
    });
    const cash = s.standings[0];
    expect(s.standings).toHaveLength(1);
    expect(cash.available).toBe(0);
    expect(cash.freeToMove).toBe(0);
    expect(cash.isBelowFloor).toBe(true);
  });

  it('bills pinned to an account reduce what can leave it', () => {
    const s = buildSnapshot({
      accounts: [acc('momo', 'Mobile Money', 1500, { kind: 'momo' })],
      txns: [],
      obligations: [
        obl({ name: 'Rent', amount: 1200, nextDue: makeDate(2026, 7, 28), accountId: 'momo' }),
        salaryJul31(),
      ],
      now,
    });
    const momo = s.standings[0];
    expect(momo.available).toBe(1500);
    expect(momo.committed).toBe(1200);
    expect(momo.freeToMove).toBe(300);
  });
});

describe('runway', () => {
  it('burn rate is measured over the days actually observed', () => {
    const s = buildSnapshot({ accounts: [acc('a', 'Fidelity', 3000)], txns: steadySpending('a'), now });
    expect(s.dailyBurn).toBeCloseTo(50, 3);
    expect(s.runwayDays).toBeCloseTo(60, 3);
  });

  it('falling short before payday is detected', () => {
    const s = buildSnapshot({
      accounts: [acc('a', 'Fidelity', 500)],
      txns: steadySpending('a'),
      obligations: [salaryJul31()],
      now,
    });
    expect(s.runwayDays).toBeCloseTo(10, 3);
    expect(s.daysUntilIncome).toBe(16);
    expect(s.willFallShort).toBe(true);
    expect(s.shortfallDays).toBe(6);
  });

  it('no spending means no runway figure rather than a wrong one', () => {
    const s = buildSnapshot({ accounts: [acc('a', 'Fidelity', 3000)], txns: [], now });
    expect(s.dailyBurn).toBe(0);
    expect(s.runwayDays).toBeNull();
    expect(s.willFallShort).toBe(false);
  });
});

describe('category movement', () => {
  it('this month is compared against the one before it', () => {
    const s = buildSnapshot({
      accounts: [acc('a', 'Fidelity', 3000)],
      txns: [
        txn({ account: 'a', type: 'Expense', amount: 400, date: daysAgo(5) }),
        txn({ account: 'a', type: 'Expense', amount: 200, date: daysAgo(45) }),
      ],
      now,
    });
    const food = s.categories.find((c) => c.category === 'Food & Dining')!;
    expect(food.amount).toBe(400);
    expect(food.previousAmount).toBe(200);
    expect(food.changeRatio).toBeCloseTo(1.0, 3);
  });
});

describe('obligation recurrence', () => {
  it('a monthly bill reports every landing in the window', () => {
    const rent = obl({ name: 'Rent', amount: 1200, nextDue: makeDate(2026, 7, 28) });
    expect(rent.occurrencesBetween(makeDate(2026, 7, 1), makeDate(2026, 10, 1))).toEqual([
      makeDate(2026, 7, 28),
      makeDate(2026, 8, 28),
      makeDate(2026, 9, 28),
    ]);
  });

  it('an anchor left in the past still rolls forward correctly', () => {
    const rent = obl({ name: 'Rent', amount: 1200, nextDue: makeDate(2025, 1, 5) });
    expect(rent.nextOccurrenceOnOrAfter(makeDate(2026, 7, 15))).toEqual(makeDate(2026, 8, 5));
  });

  it('month-end dates clamp instead of overflowing', () => {
    const bill = obl({ name: 'Loan', amount: 300, nextDue: makeDate(2026, 1, 31) });
    expect(bill.occurrencesBetween(makeDate(2026, 1, 1), makeDate(2026, 4, 1))).toEqual([
      makeDate(2026, 1, 31),
      makeDate(2026, 2, 28),
      makeDate(2026, 3, 28),
    ]);
  });

  it('a one-off lands exactly once', () => {
    const o = obl({ name: 'School fees', amount: 2500, nextDue: makeDate(2026, 8, 10), cadence: 'once' });
    expect(o.occurrencesBetween(makeDate(2026, 7, 1), makeDate(2027, 7, 1))).toEqual([
      makeDate(2026, 8, 10),
    ]);
    expect(o.occurrencesBetween(makeDate(2026, 9, 1), makeDate(2027, 7, 1))).toEqual([]);
  });
});

describe('horizon', () => {
  it('an imminent payday does not shrink the window below a week', () => {
    const s = buildSnapshot({
      accounts: [acc('a', 'Fidelity', 3000)],
      txns: [],
      obligations: [
        obl({ name: 'Salary', amount: 4000, nextDue: makeDate(2026, 7, 16), direction: 'in' }),
      ],
      now,
    });
    expect(s.daysUntilIncome).toBe(1);
    expect(s.horizon).toEqual(addDays(now, MIN_HORIZON_DAYS));
  });

  it('with no known income the window falls back to 30 days', () => {
    const s = buildSnapshot({ accounts: [acc('a', 'Fidelity', 3000)], txns: [], now });
    expect(s.daysUntilIncome).toBeNull();
    expect(s.horizon).toEqual(addDays(now, DEFAULT_HORIZON_DAYS));
  });
});
