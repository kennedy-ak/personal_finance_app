// Parity port of test/alerts_test.dart.

import { describe, expect, it } from 'vitest';
import { makeDate } from '@/lib/dates';
import { type Account } from '@/lib/domain/account';
import { type Goal } from '@/lib/domain/goal';
import { type Obligation } from '@/lib/domain/obligation';
import { type Txn } from '@/lib/domain/transaction';
import { acc, daysAgo, goal, now, obl, salary, steadySpending, txn } from '@/test/fixtures';
import { buildAlerts, type MoneyAlert } from './alerts';
import { buildSnapshot } from './money-engine';

function alertsFor({
  accounts,
  txns = [],
  obligations = [],
  goals = [],
}: {
  accounts: Account[];
  txns?: Txn[];
  obligations?: Obligation[];
  goals?: Goal[];
}): MoneyAlert[] {
  const snapshot = buildSnapshot({ accounts, txns, obligations, goals, now });
  return buildAlerts({ snapshot, obligations, goals, now });
}

const find = (alerts: MoneyAlert[], id: string) => alerts.find((a) => a.id === id);

const rentOn = (y: number, m: number, d: number, accountId?: string, amount = 1200) =>
  obl({ name: 'Rent', amount, nextDue: makeDate(y, m, d), accountId });

describe('setup nudges', () => {
  it('asks for an income date when none is known', () => {
    expect(find(alertsFor({ accounts: [acc('a', 'Fidelity', 3000)] }), 'setup.no-income')).toBeDefined();
  });

  it('stays quiet once income is recorded', () => {
    const alerts = alertsFor({ accounts: [acc('a', 'Fidelity', 3000)], obligations: [salary] });
    expect(find(alerts, 'setup.no-income')).toBeUndefined();
  });
});

describe('running short before payday', () => {
  it('fires with the daily cut needed to close the gap', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 500)],
      txns: steadySpending('a'),
      obligations: [salary],
    });
    const alert = find(alerts, 'cash.shortfall')!;
    expect(alert).toBeDefined();
    expect(alert.severity).toBe('critical');
    expect(alert.title).toContain('6 days before payday');
    expect(alert.detail).toContain('31.25');
  });

  it('stays quiet when the cash comfortably outlasts the wait', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 5000)],
      txns: steadySpending('a'),
      obligations: [salary],
    });
    expect(find(alerts, 'cash.shortfall')).toBeUndefined();
  });
});

describe('overcommitted', () => {
  it('fires when bills exceed spendable money', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 1000)],
      obligations: [salary, rentOn(2026, 7, 25, undefined, 1500)],
    });
    const alert = find(alerts, 'cash.overcommitted')!;
    expect(alert).toBeDefined();
    expect(alert.severity).toBe('critical');
    expect(alert.title).toContain('500');
  });

  it('stays quiet when bills fit', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 3000)],
      obligations: [salary, rentOn(2026, 7, 25, undefined, 1500)],
    });
    expect(find(alerts, 'cash.overcommitted')).toBeUndefined();
  });
});

describe('accounts below their floor', () => {
  it('names the account that should top it up', () => {
    const alerts = alertsFor({
      accounts: [
        acc('fid', 'Fidelity', 3000),
        acc('cash', 'Cash', 120, { kind: 'cash', minBalance: 300 }),
      ],
      obligations: [salary],
    });
    const alert = find(alerts, 'account.below-floor.cash')!;
    expect(alert.title).toBe('Move GHS 180.00 from Fidelity to Cash');
    expect(alert.actionRoute).toBe('/add');
  });

  it('says so plainly when nothing can cover the gap', () => {
    const alerts = alertsFor({
      accounts: [acc('cash', 'Cash', 120, { kind: 'cash', minBalance: 300 })],
      obligations: [salary],
    });
    const alert = find(alerts, 'account.below-floor.cash')!;
    expect(alert.title).toBe('Cash is below the floor you set');
    expect(alert.detail).toContain('No other account');
    expect(alert.actionRoute ?? null).toBeNull();
  });
});

describe('bills the account cannot cover', () => {
  it('warns before the money is due to leave', () => {
    const alerts = alertsFor({
      accounts: [acc('fid', 'Fidelity', 3000), acc('momo', 'Mobile Money', 450, { kind: 'momo' })],
      obligations: [salary, rentOn(2026, 7, 18, 'momo')],
    });
    const alert = alerts.find((a) => a.id.startsWith('bill.uncovered.'))!;
    expect(alert.severity).toBe('critical');
    expect(alert.title).toContain('Move GHS 750.00 to Mobile Money');
    expect(alert.detail).toContain('in 3 days');
    expect(alert.detail).toContain('Fidelity');
  });

  it('ignores a bill the account can already cover', () => {
    const alerts = alertsFor({
      accounts: [acc('momo', 'Mobile Money', 2000, { kind: 'momo' })],
      obligations: [salary, rentOn(2026, 7, 18, 'momo')],
    });
    expect(alerts.filter((a) => a.id.startsWith('bill.uncovered.'))).toHaveLength(0);
  });

  it('ignores a bill still far away', () => {
    const alerts = alertsFor({
      accounts: [acc('momo', 'Mobile Money', 100, { kind: 'momo' })],
      obligations: [salary, rentOn(2026, 8, 20, 'momo')],
    });
    expect(alerts.filter((a) => a.id.startsWith('bill.uncovered.'))).toHaveLength(0);
  });

  it('respects the floor when judging what is available', () => {
    const alerts = alertsFor({
      accounts: [
        acc('fid', 'Fidelity', 3000),
        acc('momo', 'Mobile Money', 1300, { kind: 'momo', minBalance: 500 }),
      ],
      obligations: [salary, rentOn(2026, 7, 18, 'momo')],
    });
    const alert = alerts.find((a) => a.id.startsWith('bill.uncovered.'))!;
    expect(alert.title).toContain('GHS 400.00');
  });
});

describe('category spikes', () => {
  it('flags a category that jumped', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 5000)],
      txns: [
        txn({ account: 'a', type: 'Expense', amount: 600, date: daysAgo(5) }),
        txn({ account: 'a', type: 'Expense', amount: 300, date: daysAgo(45) }),
      ],
      obligations: [salary],
    });
    expect(find(alerts, 'category.spike.Food & Dining')!.title).toContain('100%');
  });

  it('ignores a big percentage on a trivial amount', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 5000)],
      txns: [
        txn({ account: 'a', type: 'Expense', amount: 30, date: daysAgo(5) }),
        txn({ account: 'a', type: 'Expense', amount: 5, date: daysAgo(45) }),
      ],
      obligations: [salary],
    });
    expect(find(alerts, 'category.spike.Food & Dining')).toBeUndefined();
  });

  it('a transfer can never look like a spending spike', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 5000), acc('b', 'Cash', 500)],
      txns: [
        txn({ account: 'a', to: 'b', type: 'Transfer', amount: 2000, category: 'Transfer', date: daysAgo(5) }),
      ],
      obligations: [salary],
    });
    expect(alerts.filter((a) => a.id.startsWith('category.spike.'))).toHaveLength(0);
  });
});

describe('idle cash', () => {
  it('offers spare money to the highest-priority goal', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 5000)],
      txns: steadySpending('a'),
      obligations: [salary],
      goals: [goal({ name: 'Emergency fund', target: 10000, saved: 0 })],
    });
    const alert = alerts.find((a) => a.id.startsWith('goal.top-up.'))!;
    expect(alert.severity).toBe('info');
    expect(alert.title).toContain('Emergency fund');
  });

  it('never offers money the user needs to live on', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 800)],
      txns: steadySpending('a'),
      obligations: [salary],
      goals: [goal({ name: 'Emergency fund', target: 10000, saved: 0 })],
    });
    expect(alerts.filter((a) => a.id.startsWith('goal.top-up.'))).toHaveLength(0);
  });

  it('stays quiet when there is no goal to fund', () => {
    const alerts = alertsFor({
      accounts: [acc('a', 'Fidelity', 5000)],
      txns: steadySpending('a'),
      obligations: [salary],
    });
    expect(alerts.filter((a) => a.id.startsWith('goal.top-up.'))).toHaveLength(0);
  });
});

it('the worst news comes first', () => {
  const alerts = alertsFor({
    accounts: [
      acc('a', 'Fidelity', 500),
      acc('cash', 'Cash', 50, { kind: 'cash', minBalance: 300 }),
    ],
    txns: steadySpending('a'),
    obligations: [salary],
  });
  const rank = { critical: 0, warning: 1, info: 2 } as const;
  const ranks = alerts.map((a) => rank[a.severity]);
  expect(alerts[0].severity).toBe('critical');
  expect(ranks).toEqual([...ranks].sort((x, y) => x - y));
});
