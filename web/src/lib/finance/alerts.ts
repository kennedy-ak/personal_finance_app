/**
 * Port of lib/core/finance/alerts.dart.
 *
 * Detection is deterministic on purpose. A model asked to spot problems will
 * invent them; a rule that fires on `runway < daysUntilIncome` cannot.
 */

import { addDays, diffDays, isAfter, type DateOnly } from '../dates';
import { type Goal } from '../domain/goal';
import { type Obligation } from '../domain/obligation';
import { dateLong, formatMoney } from '../format';
import { type AccountStanding, type MoneySnapshot } from './money-engine';

/** Ordered loudest first; the order is the sort key. */
export type AlertSeverity = 'critical' | 'warning' | 'info';

const SEVERITY_RANK: Record<AlertSeverity, number> = {
  critical: 0,
  warning: 1,
  info: 2,
};

export interface MoneyAlert {
  /** Stable across rebuilds. */
  id: string;
  severity: AlertSeverity;
  /** The verb. What to do, not what happened. */
  title: string;
  /** The evidence, with real figures. */
  detail: string;
  actionLabel?: string | null;
  actionRoute?: string | null;
}

/** A category must move by this fraction *and* this many cedis to matter. */
export const CATEGORY_SPIKE_RATIO = 0.35;
export const CATEGORY_SPIKE_FLOOR = 100;

/** How far ahead to warn about a bill whose account cannot cover it. */
export const BILL_WARNING_DAYS = 7;

/** Idle cash is only worth flagging once it is a meaningful sum. */
export const IDLE_CASH_FLOOR = 500;

export function buildAlerts({
  snapshot,
  obligations = [],
  goals = [],
  now,
}: {
  snapshot: MoneySnapshot;
  obligations?: Obligation[];
  goals?: Goal[];
  now?: DateOnly;
}): MoneyAlert[] {
  const asOf = now ?? snapshot.asOf;
  const out: MoneyAlert[] = [
    ...setupGaps(obligations),
    ...shortfall(snapshot),
    ...overcommitted(snapshot),
    ...accountsBelowFloor(snapshot),
    ...billsWithoutCover(snapshot, obligations, asOf),
    ...categorySpikes(snapshot),
    ...idleCash(snapshot, goals),
  ];
  // Stable sort, loudest first.
  return out
    .map((a, i) => ({ a, i }))
    .sort((x, y) => SEVERITY_RANK[x.a.severity] - SEVERITY_RANK[y.a.severity] || x.i - y.i)
    .map((x) => x.a);
}

function setupGaps(obligations: Obligation[]): MoneyAlert[] {
  const hasIncome = obligations.some((o) => o.isActive && !o.isOutflow);
  if (hasIncome) return [];
  return [
    {
      id: 'setup.no-income',
      severity: 'info',
      title: 'Tell the app when you get paid',
      detail:
        'Without an expected income date there is no way to know whether your ' +
        'money has to last three days or thirty.',
      actionLabel: 'Add income',
      actionRoute: '/plan',
    },
  ];
}

function shortfall(s: MoneySnapshot): MoneyAlert[] {
  if (!s.willFallShort) return [];
  const days = s.daysUntilIncome!;
  const sustainable = days <= 0 ? 0 : s.usableCash / days;
  const cut = s.dailyBurn - sustainable;
  return [
    {
      id: 'cash.shortfall',
      severity: 'critical',
      title: `You run out ${s.shortfallDays} days before payday`,
      detail:
        `At ${formatMoney(s.dailyBurn)} a day your ${formatMoney(s.usableCash)} lasts ` +
        `${Math.floor(s.runwayDays!)} days, and income is ${days} days away. ` +
        `Spending ${formatMoney(sustainable)} a day instead closes the gap — ` +
        `about ${formatMoney(cut)} less each day.`,
      actionLabel: 'See spending',
      actionRoute: '/history',
    },
  ];
}

function overcommitted(s: MoneySnapshot): MoneyAlert[] {
  if (s.safeToSpend >= 0) return [];
  return [
    {
      id: 'cash.overcommitted',
      severity: 'critical',
      title: `Your bills exceed your spendable money by ${formatMoney(-s.safeToSpend)}`,
      detail:
        `${formatMoney(s.usableCash)} is available and ${formatMoney(s.committed)} is ` +
        `already committed before ${dateLong(s.horizon)}. Something has to ` +
        'move — a locked account, a goal, or a bill date.',
      actionLabel: 'Review commitments',
      actionRoute: '/plan',
    },
  ];
}

function accountsBelowFloor(s: MoneySnapshot): MoneyAlert[] {
  const out: MoneyAlert[] = [];
  for (const standing of s.standings.filter((x) => x.isBelowFloor)) {
    const a = standing.account;
    const gap = a.minBalance - a.balance;
    const source = bestSourceExcluding(s, a.id, gap);
    out.push({
      id: `account.below-floor.${a.id}`,
      severity: 'warning',
      title:
        source === null
          ? `${a.name} is below the floor you set`
          : `Move ${formatMoney(gap)} from ${source.account.name} to ${a.name}`,
      detail:
        `${a.name} holds ${formatMoney(a.balance)} but you asked to keep at ` +
        `least ${formatMoney(a.minBalance)}` +
        (source === null ? `. No other account has ${formatMoney(gap)} free.` : '.'),
      actionLabel: source === null ? null : 'Transfer',
      actionRoute: source === null ? null : '/add',
    });
  }
  return out;
}

function billsWithoutCover(
  s: MoneySnapshot,
  obligations: Obligation[],
  asOf: DateOnly,
): MoneyAlert[] {
  const out: MoneyAlert[] = [];
  const deadline = addDays(asOf, BILL_WARNING_DAYS);
  const standings = new Map(s.standings.map((x) => [x.account.id, x]));

  for (const o of obligations.filter((o) => o.isActive && o.isOutflow)) {
    const acc = o.accountId;
    if (acc === null) continue;
    const standing = standings.get(acc);
    if (standing === undefined) continue;

    const due = o.nextOccurrenceOnOrAfter(asOf);
    if (due === null || isAfter(due, deadline)) continue;
    if (standing.available >= o.amount) continue;

    const gap = o.amount - standing.available;
    const source = bestSourceExcluding(s, acc, gap);
    const daysAway = diffDays(due, asOf);
    const when = daysAway <= 0 ? 'today' : `in ${daysAway} days`;

    out.push({
      id: `bill.uncovered.${o.id}`,
      severity: 'critical',
      title:
        source === null
          ? `${o.name} will bounce ${when}`
          : `Move ${formatMoney(gap)} to ${standing.account.name} before ${o.name}`,
      detail:
        `${o.name} takes ${formatMoney(o.amount)} from ` +
        `${standing.account.name} ${when}, but only ${formatMoney(standing.available)} ` +
        'is free there' +
        (source === null
          ? ` and nothing else has ${formatMoney(gap)} spare.`
          : `. ${source.account.name} has ${formatMoney(source.freeToMove)} spare.`),
      actionLabel: source === null ? 'Review' : 'Transfer',
      actionRoute: source === null ? '/plan' : '/add',
    });
  }
  return out;
}

function categorySpikes(s: MoneySnapshot): MoneyAlert[] {
  const out: MoneyAlert[] = [];
  for (const c of s.categories) {
    const ratio = c.changeRatio;
    if (ratio === null || ratio < CATEGORY_SPIKE_RATIO) continue;
    if (c.delta < CATEGORY_SPIKE_FLOOR) continue;
    out.push({
      id: `category.spike.${c.category}`,
      severity: 'warning',
      title: `${c.category} is up ${Math.round(ratio * 100)}% this month`,
      detail:
        `${formatMoney(c.amount)} in the last 30 days against ` +
        `${formatMoney(c.previousAmount)} the 30 days before — ` +
        `${formatMoney(c.delta)} more.`,
      actionLabel: 'See transactions',
      actionRoute: '/history',
    });
  }
  // One spike is a signal; five is noise.
  return out.slice(0, 2);
}

function idleCash(s: MoneySnapshot, goals: Goal[]): MoneyAlert[] {
  if (s.safeToSpend < IDLE_CASH_FLOOR) return [];
  const underfunded = goals
    .filter((g) => g.isActive && !g.isComplete)
    .sort((a, b) => a.priority - b.priority);
  if (underfunded.length === 0) return [];

  const goal = underfunded[0];
  // Never suggest moving money the user still needs to live on.
  const spare = s.safeToSpend - s.dailyBurn * 14;
  if (spare < IDLE_CASH_FLOOR) return [];

  const amount = spare < goal.remaining ? spare : goal.remaining;
  return [
    {
      id: `goal.top-up.${goal.id}`,
      severity: 'info',
      title: `Put ${formatMoney(amount)} towards ${goal.name}`,
      detail:
        `You have ${formatMoney(s.safeToSpend)} spendable and only need about ` +
        `${formatMoney(s.dailyBurn * 14)} for the next two weeks. ` +
        `${goal.name} still needs ${formatMoney(goal.remaining)}.`,
      actionLabel: 'Open goals',
      actionRoute: '/plan',
    },
  ];
}

function bestSourceExcluding(
  s: MoneySnapshot,
  excludeId: string,
  amount: number,
): AccountStanding | null {
  for (const c of s.movableSources) {
    if (c.account.id === excludeId) continue;
    if (c.freeToMove >= amount) return c;
  }
  return null;
}
