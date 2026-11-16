/**
 * Port of lib/core/finance/money_engine.dart.
 *
 * Turns raw balances and history into the handful of figures that answer a
 * question. Pure and deterministic: same inputs, same numbers, no network, no
 * clock reads beyond the `now` passed in. The coach is told these numbers, so
 * arithmetic happens here, where it is tested, and the model only phrases it.
 *
 * Keep this in step with the Dart original — the parity tests in
 * money-engine.test.ts are the Dart tests restated.
 */

import { addDays, diffDays, isAfter, isBefore, today, type DateOnly } from '../dates';
import { type Account } from '../domain/account';
import { type Goal } from '../domain/goal';
import { type Obligation } from '../domain/obligation';
import { type Txn } from '../domain/transaction';

/** Spending in one category over a window, against the window before it. */
export class CategorySpend {
  constructor(
    readonly category: string,
    readonly amount: number,
    readonly previousAmount: number,
  ) {}

  get delta(): number {
    return this.amount - this.previousAmount;
  }

  /** 0.38 == up 38%. Null when there is no prior spending to compare. */
  get changeRatio(): number | null {
    return this.previousAmount <= 0
      ? null
      : (this.amount - this.previousAmount) / this.previousAmount;
  }
}

/** One account, with the part of its balance that is genuinely usable. */
export class AccountStanding {
  constructor(
    readonly account: Account,
    /** Balance minus the floor, never below zero. */
    readonly available: number,
    /** Obligations pinned to this account landing before the horizon. */
    readonly committed: number,
  ) {}

  /** What could leave without breaking a floor or a known bill. */
  get freeToMove(): number {
    const free = this.available - this.committed;
    return free > 0 ? free : 0;
  }

  get isBelowFloor(): boolean {
    return this.account.isBelowFloor;
  }
}

export class MoneySnapshot {
  constructor(
    readonly asOf: DateOnly,
    /** End of the window safeToSpend and committed cover — normally next income. */
    readonly horizon: DateOnly,
    readonly totalBalance: number,
    readonly liquid: number,
    readonly reserved: number,
    readonly locked: number,
    /** Sum of minimum balances on liquid accounts. */
    readonly floors: number,
    /** Goal savings inside the liquid pool, held back from spending. */
    readonly goalReserve: number,
    /** Bills landing between now and horizon. */
    readonly committed: number,
    readonly expectedIncome: number,
    /** Liquid money left after floors, goals and everything already owed. */
    readonly safeToSpend: number,
    /** Average real spending per day. Transfers excluded. */
    readonly dailyBurn: number,
    /** Days the usable cash lasts at dailyBurn. Null when nothing is spent. */
    readonly runwayDays: number | null,
    /** Days until money next arrives. Null when nothing is known. */
    readonly daysUntilIncome: number | null,
    readonly standings: AccountStanding[],
    readonly categories: CategorySpend[],
    readonly spend30d: number,
    readonly income30d: number,
    readonly prevSpend30d: number,
  ) {}

  get spendChangeRatio(): number | null {
    return this.prevSpend30d <= 0
      ? null
      : (this.spend30d - this.prevSpend30d) / this.prevSpend30d;
  }

  /** Liquid money after floors and goals, before bills. */
  get usableCash(): number {
    return this.liquid - this.floors - this.goalReserve;
  }

  /** True when the cash runs out before the next money arrives. */
  get willFallShort(): boolean {
    const r = this.runwayDays;
    const d = this.daysUntilIncome;
    if (r === null || d === null) return false;
    return r < d;
  }

  get shortfallDays(): number {
    if (!this.willFallShort) return 0;
    return Math.ceil(this.daysUntilIncome! - this.runwayDays!);
  }

  /** Accounts with money to spare, most first. */
  get movableSources(): AccountStanding[] {
    return this.standings
      .filter((s) => !s.account.isArchived && s.freeToMove > 0)
      .sort((a, b) => b.freeToMove - a.freeToMove);
  }
}

/** Days of history used to establish a spending rate. */
export const BURN_WINDOW_DAYS = 60;

/** Shortest horizon safeToSpend will ever cover. */
export const MIN_HORIZON_DAYS = 7;

/** Horizon used when nothing is known about future income. */
export const DEFAULT_HORIZON_DAYS = 30;

export interface SnapshotInput {
  accounts: Account[];
  txns: Txn[];
  obligations?: Obligation[];
  goals?: Goal[];
  now?: DateOnly;
}

export function buildSnapshot({
  accounts,
  txns,
  obligations = [],
  goals = [],
  now,
}: SnapshotInput): MoneySnapshot {
  const asOf = now ?? today();
  const live = accounts.filter((a) => !a.isArchived);
  const byId = new Map(live.map((a) => [a.id, a]));

  // --- Where the money sits ------------------------------------------------
  let liquid = 0,
    reserved = 0,
    locked = 0,
    floors = 0;
  for (const a of live) {
    switch (a.liquidity) {
      case 'liquid':
        liquid += a.balance;
        floors += a.minBalance;
        break;
      case 'reserved':
        reserved += a.balance;
        break;
      case 'locked':
        locked += a.balance;
        break;
    }
  }
  const totalBalance = live.reduce((s, a) => s + a.balance, 0);

  // --- When does money next arrive? ---------------------------------------
  const activeObs = obligations.filter((o) => o.isActive);
  const incomeObs = activeObs.filter((o) => !o.isOutflow);

  let nextIncome: DateOnly | null = null;
  for (const o of incomeObs) {
    const hit = o.nextOccurrenceOnOrAfter(addDays(asOf, 1));
    if (hit === null) continue;
    if (nextIncome === null || isBefore(hit, nextIncome)) nextIncome = hit;
  }

  const earliestHorizon = addDays(asOf, MIN_HORIZON_DAYS);
  const horizon =
    nextIncome === null
      ? addDays(asOf, DEFAULT_HORIZON_DAYS)
      : isBefore(nextIncome, earliestHorizon)
        ? earliestHorizon
        : nextIncome;

  const daysUntilIncome = nextIncome === null ? null : diffDays(nextIncome, asOf);

  // --- What is already spoken for -----------------------------------------
  const windowStart = addDays(asOf, 1);
  let committed = 0,
    expectedIncome = 0;
  const committedByAccount = new Map<string, number>();

  for (const o of activeObs) {
    const due = o.amountDueBetween(windowStart, horizon);
    if (due <= 0) continue;
    if (o.isOutflow) {
      committed += due;
      const acc = o.accountId;
      if (acc !== null && byId.has(acc)) {
        committedByAccount.set(acc, (committedByAccount.get(acc) ?? 0) + due);
      }
    } else {
      expectedIncome += due;
    }
  }

  // --- Money that exists but is not for spending --------------------------
  // Only goal savings sitting in the liquid pool. A goal parked in a locked
  // account is already outside `liquid`; reserving it again double-counts.
  let goalReserve = 0;
  for (const g of goals.filter((g) => g.isActive)) {
    const acc = g.accountId;
    if (acc === null) {
      goalReserve += g.savedAmount;
      continue;
    }
    const home = byId.get(acc);
    if (home === undefined || home.liquidity === 'liquid') {
      goalReserve += g.savedAmount;
    }
  }

  const safeToSpend = liquid - floors - goalReserve - committed;

  // --- How fast money leaves ----------------------------------------------
  const burnStart = addDays(asOf, -BURN_WINDOW_DAYS);
  const burnTotal = txns
    .filter((t) => t.isSpending && !isBefore(t.date, burnStart) && !isAfter(t.date, asOf))
    .reduce((s, t) => s + t.amount, 0);

  // Measure over the history that exists, not the window asked for —
  // otherwise a two-week-old account looks like it barely spends.
  let oldest: DateOnly | null = null;
  for (const t of txns) {
    if (!t.isSpending) continue;
    if (oldest === null || isBefore(t.date, oldest)) oldest = t.date;
  }
  const observedDays =
    oldest === null
      ? BURN_WINDOW_DAYS
      : diffDays(asOf, isBefore(oldest, burnStart) ? burnStart : oldest) + 1;
  const dailyBurn = observedDays <= 0 ? 0 : burnTotal / observedDays;

  const usableCash = liquid - floors - goalReserve;
  const runwayDays =
    dailyBurn <= 0 ? null : usableCash <= 0 ? 0 : usableCash / dailyBurn;

  // --- Per-account standing -----------------------------------------------
  const standings = live
    .map((a) => new AccountStanding(a, a.available, committedByAccount.get(a.id) ?? 0))
    .sort((x, y) => y.freeToMove - x.freeToMove);

  // --- Trailing 30 days and category movement -----------------------------
  const cut30 = addDays(asOf, -30);
  const cut60 = addDays(asOf, -60);

  let spend30d = 0,
    income30d = 0,
    prevSpend30d = 0;
  const current = new Map<string, number>();
  const previous = new Map<string, number>();

  for (const t of txns) {
    if (!t.isRealMoneyMovement) continue;
    const inCurrent = !isBefore(t.date, cut30) && !isAfter(t.date, asOf);
    const inPrevious = !isBefore(t.date, cut60) && isBefore(t.date, cut30);
    if (t.isIncome && inCurrent) income30d += t.amount;
    if (!t.isSpending) continue;
    if (inCurrent) {
      spend30d += t.amount;
      current.set(t.category, (current.get(t.category) ?? 0) + t.amount);
    } else if (inPrevious) {
      prevSpend30d += t.amount;
      previous.set(t.category, (previous.get(t.category) ?? 0) + t.amount);
    }
  }

  const categories = [...current.entries()]
    .map(([k, v]) => new CategorySpend(k, v, previous.get(k) ?? 0))
    .sort((a, b) => b.amount - a.amount);

  return new MoneySnapshot(
    asOf,
    horizon,
    totalBalance,
    liquid,
    reserved,
    locked,
    floors,
    goalReserve,
    committed,
    expectedIncome,
    safeToSpend,
    dailyBurn,
    runwayDays,
    daysUntilIncome,
    standings,
    categories,
    spend30d,
    income30d,
    prevSpend30d,
  );
}
