// Parity port of test/payment_planner_test.dart.

import { describe, expect, it } from 'vitest';
import { makeDate } from '@/lib/dates';
import { type Account } from '@/lib/domain/account';
import { type Obligation } from '@/lib/domain/obligation';
import { acc, now, obl, salary, steadySpending } from '@/test/fixtures';
import { buildSnapshot } from './money-engine';
import { planPayment } from './payment-planner';

function planFor(
  amount: number,
  { accounts, obligations = [], payFrom }: { accounts: Account[]; obligations?: Obligation[]; payFrom?: string },
) {
  const snapshot = buildSnapshot({
    accounts,
    txns: steadySpending(accounts[0].id),
    obligations,
    now,
  });
  return planPayment({ amount, snapshot, obligations, payFromAccountId: payFrom });
}

const rentOnMomo = () =>
  obl({ name: 'Rent', amount: 1200, nextDue: makeDate(2026, 7, 28), accountId: 'momo' });

describe('picking a single source', () => {
  it('names the account and leaves the protected ones alone', () => {
    const plan = planFor(800, {
      accounts: [
        acc('fid', 'Fidelity', 3000),
        acc('cash', 'Cash', 400, { kind: 'cash', minBalance: 300 }),
        acc('momo', 'Mobile Money', 1400, { kind: 'momo' }),
      ],
      obligations: [salary, rentOnMomo()],
    });
    expect(plan.isPossible).toBe(true);
    expect(plan.isClean).toBe(true);
    expect(plan.headline).toBe('Take GHS 800.00 from Fidelity');
    expect(plan.sources).toHaveLength(1);
    expect(plan.sources[0].account.name).toBe('Fidelity');
  });

  it('explains why each other account was passed over', () => {
    const plan = planFor(800, {
      accounts: [
        acc('fid', 'Fidelity', 3000),
        acc('cash', 'Cash', 400, { kind: 'cash', minBalance: 300 }),
        acc('momo', 'Mobile Money', 1400, { kind: 'momo' }),
        acc('vault', 'Fixed deposit', 9000, { liquidity: 'locked' }),
      ],
      obligations: [salary, rentOnMomo()],
    });
    const reasons = plan.reasoning.join(' | ');
    expect(reasons).toContain('Not Mobile Money');
    expect(reasons).toContain('Rent');
    expect(reasons).toContain('GHS 1,200.00');
    expect(reasons).toContain('Not Cash');
    expect(reasons).toContain('Not Fixed deposit');
  });

  it('respects a floor rather than draining an account', () => {
    const plan = planFor(200, {
      accounts: [acc('cash', 'Cash', 400, { kind: 'cash', minBalance: 300 }), acc('fid', 'Fidelity', 900)],
      obligations: [salary],
    });
    expect(plan.sources[0].account.name).toBe('Fidelity');
  });

  it('never volunteers locked money when anything else will do', () => {
    const plan = planFor(500, {
      accounts: [acc('vault', 'Fixed deposit', 50000, { liquidity: 'locked' }), acc('fid', 'Fidelity', 800)],
      obligations: [salary],
    });
    expect(plan.sources[0].account.name).toBe('Fidelity');
  });

  it('prefers a spendable account over a reserved one', () => {
    const plan = planFor(500, {
      accounts: [acc('sch', 'School fees', 5000, { liquidity: 'reserved' }), acc('fid', 'Fidelity', 900)],
      obligations: [salary],
    });
    expect(plan.sources[0].account.name).toBe('Fidelity');
  });
});

describe('when it costs something', () => {
  it('falls back to bill money and says which bill', () => {
    const plan = planFor(1000, {
      accounts: [acc('momo', 'Mobile Money', 1400, { kind: 'momo' })],
      obligations: [salary, rentOnMomo()],
    });
    expect(plan.isPossible).toBe(true);
    expect(plan.isClean).toBe(false);
    expect(plan.sources[0].quality).toBe('dipsIntoBills');
    expect(plan.sources[0].caution).toContain('Rent');
  });

  it('falls back to breaking a floor only as a last resort', () => {
    const plan = planFor(350, {
      accounts: [acc('cash', 'Cash', 400, { kind: 'cash', minBalance: 300 })],
      obligations: [salary],
    });
    expect(plan.isPossible).toBe(true);
    expect(plan.sources[0].quality).toBe('breaksFloor');
    expect(plan.sources[0].caution).toContain('GHS 300.00');
  });

  it('warns when the payment causes a shortfall before payday', () => {
    const plan = planFor(700, { accounts: [acc('fid', 'Fidelity', 1000)], obligations: [salary] });
    expect(plan.impact.runwayDaysAfter).toBeCloseTo(6, 3);
    expect(plan.impact.daysUntilIncome).toBe(16);
    expect(plan.impact.causesShortfall).toBe(true);
    expect(plan.impact.safeToSpendAfter).toBe(300);
  });

  it('stays quiet about shortfall when the payment is comfortable', () => {
    const plan = planFor(200, { accounts: [acc('fid', 'Fidelity', 5000)], obligations: [salary] });
    expect(plan.impact.causesShortfall).toBe(false);
  });
});

describe('splitting', () => {
  it('combines accounts when no single one can cover it', () => {
    const plan = planFor(1200, {
      accounts: [acc('fid', 'Fidelity', 700), acc('momo', 'Mobile Money', 600, { kind: 'momo' })],
      obligations: [salary],
    });
    expect(plan.isPossible).toBe(true);
    expect(plan.isSplit).toBe(true);
    expect(plan.headline).toContain('Split GHS 1,200.00 across');
    expect(plan.sources.reduce((s, x) => s + x.amount, 0)).toBeCloseTo(1200, 3);
    expect(plan.sources[0].account.name).toBe('Fidelity');
    expect(plan.sources[0].amount).toBe(700);
  });

  it('prefers one account over a split when one can manage', () => {
    const plan = planFor(600, {
      accounts: [acc('fid', 'Fidelity', 700), acc('momo', 'Mobile Money', 600, { kind: 'momo' })],
      obligations: [salary],
    });
    expect(plan.isSplit).toBe(false);
  });
});

describe('when the money has to leave a particular account', () => {
  it('works out the top-up needed and where it comes from', () => {
    const plan = planFor(1000, {
      accounts: [acc('fid', 'Fidelity', 3000), acc('momo', 'Mobile Money', 400, { kind: 'momo' })],
      obligations: [salary],
      payFrom: 'momo',
    });
    expect(plan.isPossible).toBe(true);
    expect(plan.transfers).toHaveLength(1);
    expect(plan.transfers[0].from.name).toBe('Fidelity');
    expect(plan.transfers[0].to.name).toBe('Mobile Money');
    expect(plan.transfers[0].amount).toBe(600);
    expect(plan.headline).toBe('Move GHS 600.00 from Fidelity into Mobile Money first');
  });

  it('does not move money when the account already has enough', () => {
    const plan = planFor(300, {
      accounts: [acc('fid', 'Fidelity', 3000), acc('momo', 'Mobile Money', 900, { kind: 'momo' })],
      obligations: [salary],
      payFrom: 'momo',
    });
    expect(plan.transfers).toHaveLength(0);
    expect(plan.headline).toBe('Mobile Money can cover GHS 300.00');
  });

  it('draws from several accounts when one top-up is not enough', () => {
    const plan = planFor(2000, {
      accounts: [
        acc('momo', 'Mobile Money', 200, { kind: 'momo' }),
        acc('fid', 'Fidelity', 1000),
        acc('acc2', 'Access', 900),
      ],
      obligations: [salary],
      payFrom: 'momo',
    });
    expect(plan.isPossible).toBe(true);
    expect(plan.transfers).toHaveLength(2);
    expect(plan.transfers.reduce((s, t) => s + t.amount, 0)).toBeCloseTo(1800, 3);
  });

  it('says how short it still is when even that fails', () => {
    const plan = planFor(5000, {
      accounts: [acc('momo', 'Mobile Money', 200, { kind: 'momo' }), acc('fid', 'Fidelity', 1000)],
      obligations: [salary],
    });
    expect(plan.isPossible).toBe(false);
    expect(plan.headline).toContain('do not have GHS 5,000.00');
    expect(plan.reasoning.join(' ')).toContain('GHS 1,200.00');
  });
});

describe('edge cases', () => {
  it('an empty amount asks for one instead of guessing', () => {
    const plan = planFor(0, { accounts: [acc('fid', 'Fidelity', 3000)], obligations: [salary] });
    expect(plan.isPossible).toBe(false);
    expect(plan.headline).toContain('Enter an amount');
  });

  it('locked money is excluded from what you are told you have', () => {
    const plan = planFor(5000, {
      accounts: [acc('fid', 'Fidelity', 1000), acc('vault', 'Fixed deposit', 20000, { liquidity: 'locked' })],
      obligations: [salary],
    });
    expect(plan.isPossible).toBe(false);
    expect(plan.reasoning.join(' ')).toContain('GHS 20,000.00 is locked away');
  });

  it('archived accounts are never offered', () => {
    const plan = planFor(500, {
      accounts: [acc('old', 'Closed account', 9000, { archived: true }), acc('fid', 'Fidelity', 800)],
      obligations: [salary],
    });
    expect(plan.sources[0].account.name).toBe('Fidelity');
  });
});
