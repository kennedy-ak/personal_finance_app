/** Port of test/support/fixtures.dart — same "today", same helpers. */

import { addDays, makeDate, type DateOnly } from '@/lib/dates';
import { Account, type AccountKind, type Liquidity } from '@/lib/domain/account';
import { Goal } from '@/lib/domain/goal';
import { Obligation, type Cadence, type ObligationDirection } from '@/lib/domain/obligation';
import { Txn, type TxnType } from '@/lib/domain/transaction';

/** Fixed "today" so nothing in the suite depends on when it runs. */
export const now = makeDate(2026, 7, 15);

export const daysAgo = (n: number) => addDays(now, -n);

export function acc(
  id: string,
  name: string,
  balance: number,
  opts: {
    kind?: AccountKind;
    liquidity?: Liquidity;
    minBalance?: number;
    archived?: boolean;
  } = {},
): Account {
  return new Account(
    id,
    'u1',
    name,
    balance,
    opts.kind ?? 'bank',
    opts.liquidity ?? 'liquid',
    opts.minBalance ?? 0,
    null,
    0,
    opts.archived ?? false,
    0,
    new Date(Date.UTC(2025, 0, 1)),
  );
}

export function txn(o: {
  account: string;
  type: TxnType;
  amount: number;
  date: DateOnly;
  category?: string;
  to?: string;
}): Txn {
  return new Txn(
    `t${o.date.getTime()}${o.amount}${o.account}`,
    'u1',
    o.account,
    o.to ?? null,
    o.type,
    o.amount,
    o.category ?? 'Food & Dining',
    null,
    o.date,
    o.date,
  );
}

export function obl(o: {
  name: string;
  amount: number;
  nextDue: DateOnly;
  direction?: ObligationDirection;
  cadence?: Cadence;
  accountId?: string;
}): Obligation {
  return new Obligation(
    `o${o.name}`,
    'u1',
    o.name,
    o.direction ?? 'out',
    o.amount,
    o.cadence ?? 'monthly',
    o.nextDue,
    o.accountId ?? null,
    null,
    true,
    new Date(Date.UTC(2025, 0, 1)),
  );
}

export function goal(o: {
  name: string;
  target: number;
  saved: number;
  accountId?: string;
  priority?: number;
}): Goal {
  return new Goal(
    `g${o.name}`,
    'u1',
    o.name,
    o.target,
    o.saved,
    null,
    o.accountId ?? null,
    o.priority ?? 0,
    true,
    new Date(Date.UTC(2025, 0, 1)),
  );
}

/** GHS 3,000 spread over exactly 60 days, so the burn rate is a clean 50/day. */
export function steadySpending(account: string): Txn[] {
  return [
    txn({ account, type: 'Expense', amount: 1500, date: daysAgo(59) }),
    txn({ account, type: 'Expense', amount: 1500, date: daysAgo(1) }),
  ];
}

export const salary = obl({
  name: 'Salary',
  amount: 4000,
  nextDue: makeDate(2026, 7, 31),
  direction: 'in',
});
