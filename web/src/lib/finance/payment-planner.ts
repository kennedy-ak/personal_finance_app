/**
 * Port of lib/core/finance/payment_planner.dart.
 *
 * Answers: *I need to send this money — where should it come from?*
 * Deterministic and explainable: every account passed over carries the reason.
 */

import { isAfter } from '../dates';
import { type Account, type Liquidity } from '../domain/account';
import { type Obligation } from '../domain/obligation';
import { dateLong, formatMoney } from '../format';
import { type AccountStanding, type MoneySnapshot } from './money-engine';

/** How much damage taking money from an account would do. Ordered. */
export type SourceQuality = 'clean' | 'dipsIntoBills' | 'breaksFloor' | 'insufficient';

const QUALITY_RANK: Record<SourceQuality, number> = {
  clean: 0,
  dipsIntoBills: 1,
  breaksFloor: 2,
  insufficient: 3,
};

const USABLE_QUALITIES: SourceQuality[] = ['clean', 'dipsIntoBills', 'breaksFloor'];

export class PaymentCandidate {
  constructor(
    readonly standing: AccountStanding,
    readonly quality: SourceQuality,
    /** Why this account is not ideal, in the user's terms. Null when it is. */
    readonly caution: string | null,
  ) {}

  get account(): Account {
    return this.standing.account;
  }
  get spare(): number {
    return this.standing.freeToMove;
  }
  get aboveFloor(): number {
    return this.standing.available;
  }
  get everything(): number {
    return this.standing.account.balance;
  }

  capacityFor(q: SourceQuality): number {
    switch (q) {
      case 'clean':
        return this.spare;
      case 'dipsIntoBills':
        return this.aboveFloor;
      case 'breaksFloor':
        return this.everything;
      case 'insufficient':
        return 0;
    }
  }
}

export interface PaymentSource {
  account: Account;
  amount: number;
  quality: SourceQuality;
  caution: string | null;
}

export interface PaymentTransfer {
  from: Account;
  to: Account;
  amount: number;
}

export class PaymentImpact {
  constructor(
    readonly safeToSpendAfter: number,
    readonly runwayDaysAfter: number | null,
    readonly daysUntilIncome: number | null,
  ) {}

  /** True when the payment makes money run out before more arrives. */
  get causesShortfall(): boolean {
    const r = this.runwayDaysAfter;
    const d = this.daysUntilIncome;
    if (r === null || d === null) return false;
    return r < d;
  }
}

export class PaymentPlan {
  constructor(
    readonly amount: number,
    readonly isPossible: boolean,
    readonly sources: PaymentSource[],
    readonly transfers: PaymentTransfer[],
    readonly headline: string,
    readonly reasoning: string[],
    readonly impact: PaymentImpact,
  ) {}

  get isSplit(): boolean {
    return this.sources.length > 1;
  }

  get isClean(): boolean {
    return this.isPossible && this.sources.every((s) => s.quality === 'clean');
  }
}

/** Ranks every account for a payment of `amount`, worst reason last. */
export function rankSources({
  snapshot,
  amount,
  obligations = [],
  excludeAccountId,
}: {
  snapshot: MoneySnapshot;
  amount: number;
  obligations?: Obligation[];
  excludeAccountId?: string | null;
}): PaymentCandidate[] {
  const candidates: PaymentCandidate[] = [];

  for (const standing of snapshot.standings) {
    const a = standing.account;
    if (a.isArchived) continue;
    if (a.id === excludeAccountId) continue;
    const quality = qualityFor(standing, amount);
    candidates.push(
      new PaymentCandidate(standing, quality, cautionFor(standing, quality, obligations, snapshot)),
    );
  }

  candidates.sort((x, y) => {
    // Spendable first, then reserved, then locked.
    const byLiquidity = liquidityRank(x.account.liquidity) - liquidityRank(y.account.liquidity);
    if (byLiquidity !== 0) return byLiquidity;
    const byQuality = QUALITY_RANK[x.quality] - QUALITY_RANK[y.quality];
    if (byQuality !== 0) return byQuality;
    // Among equals, take from wherever leaves the most room behind.
    return y.spare - amount - (x.spare - amount);
  });

  return candidates;
}

/**
 * Works out where a payment should come from, and what it costs.
 * `payFromAccountId` forces the payment to leave a particular account; the
 * plan then covers topping that account up first.
 */
export function planPayment({
  amount,
  snapshot,
  obligations = [],
  payFromAccountId,
}: {
  amount: number;
  snapshot: MoneySnapshot;
  obligations?: Obligation[];
  payFromAccountId?: string | null;
}): PaymentPlan {
  if (amount <= 0) {
    return new PaymentPlan(
      amount,
      false,
      [],
      [],
      'Enter an amount to see where it should come from.',
      [],
      impactOf(snapshot, 0),
    );
  }

  if (payFromAccountId) {
    return planForcedSource(amount, snapshot, obligations, payFromAccountId);
  }

  const candidates = rankSources({ snapshot, amount, obligations });

  // Prefer one account that covers it outright, at the least harmful level.
  for (const quality of USABLE_QUALITIES) {
    const pick = candidates.find((c) => c.quality === quality && isUsable(c.account));
    if (!pick) continue;

    return new PaymentPlan(
      amount,
      true,
      [{ account: pick.account, amount, quality, caution: pick.caution }],
      [],
      `Take ${formatMoney(amount)} from ${pick.account.name}`,
      rejections(candidates, [pick.account.id]),
      impactOf(snapshot, amount),
    );
  }

  // No single account manages it — combine, still worst-harm-last.
  const split = splitAcross(candidates, amount);
  if (split.length > 0) {
    const names = split.map((s) => s.account.name).join(' and ');
    return new PaymentPlan(
      amount,
      true,
      split,
      [],
      `Split ${formatMoney(amount)} across ${names}`,
      rejections(
        candidates,
        split.map((s) => s.account.id),
      ),
      impactOf(snapshot, amount),
    );
  }

  const total = candidates
    .filter((c) => isUsable(c.account))
    .reduce((s, c) => s + c.everything, 0);

  return new PaymentPlan(
    amount,
    false,
    [],
    [],
    `You do not have ${formatMoney(amount)} to send`,
    [
      `Your spendable accounts hold ${formatMoney(total)} in total.`,
      ...(snapshot.locked > 0
        ? [`A further ${formatMoney(snapshot.locked)} is locked away and was not counted.`]
        : []),
    ],
    impactOf(snapshot, amount),
  );
}

function planForcedSource(
  amount: number,
  snapshot: MoneySnapshot,
  obligations: Obligation[],
  accountId: string,
): PaymentPlan {
  const target = snapshot.standings.find((s) => s.account.id === accountId);

  if (!target) {
    return new PaymentPlan(
      amount,
      false,
      [],
      [],
      'That account is no longer available.',
      [],
      impactOf(snapshot, amount),
    );
  }

  const account = target.account;
  const quality = qualityFor(target, amount);

  // It can already cover it — nothing to move.
  if (quality !== 'insufficient') {
    return new PaymentPlan(
      amount,
      true,
      [
        {
          account,
          amount,
          quality,
          caution: cautionFor(target, quality, obligations, snapshot),
        },
      ],
      [],
      `${account.name} can cover ${formatMoney(amount)}`,
      quality === 'clean' ? [] : [forcedCaution(quality, account)],
      impactOf(snapshot, amount),
    );
  }

  // Needs a top-up. Find it the same way we would find any source.
  const gap = amount - account.balance;
  const helpers = rankSources({
    snapshot,
    amount: gap,
    obligations,
    excludeAccountId: accountId,
  });

  const transfers: PaymentTransfer[] = [];
  let outstanding = gap;

  for (const q of USABLE_QUALITIES) {
    for (const c of helpers) {
      if (outstanding <= 0.005) break;
      if (!isUsable(c.account)) continue;
      if (transfers.some((t) => t.from.id === c.account.id)) continue;

      const capacity = c.capacityFor(q);
      if (capacity <= 0.005) continue;

      const take = capacity < outstanding ? capacity : outstanding;
      transfers.push({ from: c.account, to: account, amount: take });
      outstanding -= take;
    }
    if (outstanding <= 0.005) break;
  }

  if (outstanding > 0.005) {
    return new PaymentPlan(
      amount,
      false,
      [],
      [],
      `Even after moving everything, ${account.name} would be ${formatMoney(outstanding)} short`,
      rejections(helpers, []),
      impactOf(snapshot, amount),
    );
  }

  const moved = transfers
    .map((t) => `${formatMoney(t.amount)} from ${t.from.name}`)
    .join(', then ');

  return new PaymentPlan(
    amount,
    true,
    [{ account, amount, quality: 'clean', caution: null }],
    transfers,
    `Move ${moved} into ${account.name} first`,
    [
      `${account.name} holds ${formatMoney(account.balance)}, so it is ` +
        `${formatMoney(gap)} short of ${formatMoney(amount)}.`,
      ...rejections(
        helpers,
        transfers.map((t) => t.from.id),
      ),
    ],
    impactOf(snapshot, amount),
  );
}

/** Greedily combines accounts, taking the least harmful money first. */
function splitAcross(candidates: PaymentCandidate[], amount: number): PaymentSource[] {
  // Insertion-ordered, like the Dart map, so ties keep their ranking.
  const taken = new Map<string, PaymentSource>();
  let outstanding = amount;

  for (const quality of USABLE_QUALITIES) {
    for (const c of candidates) {
      if (outstanding <= 0.005) break;
      if (!isUsable(c.account)) continue;

      const already = taken.get(c.account.id)?.amount ?? 0;
      const capacity = c.capacityFor(quality) - already;
      if (capacity <= 0.005) continue;

      const take = capacity < outstanding ? capacity : outstanding;
      taken.set(c.account.id, {
        account: c.account,
        amount: already + take,
        quality,
        caution: c.caution,
      });
      outstanding -= take;
    }
    if (outstanding <= 0.005) break;
  }

  if (outstanding > 0.005) return [];
  return [...taken.values()].sort((a, b) => b.amount - a.amount);
}

function qualityFor(standing: AccountStanding, amount: number): SourceQuality {
  if (standing.freeToMove >= amount) return 'clean';
  if (standing.available >= amount) return 'dipsIntoBills';
  if (standing.account.balance >= amount) return 'breaksFloor';
  return 'insufficient';
}

function cautionFor(
  standing: AccountStanding,
  quality: SourceQuality,
  obligations: Obligation[],
  snapshot: MoneySnapshot,
): string | null {
  const a = standing.account;

  if (a.liquidity === 'locked') {
    return `${a.name} is locked away for the long term.`;
  }
  if (a.liquidity === 'reserved') {
    return `${a.name} is money you set aside${a.purpose === null ? '' : ` — ${a.purpose}`}.`;
  }

  switch (quality) {
    case 'clean':
      return null;
    case 'dipsIntoBills':
      return `This eats into ${billNames(a.id, obligations, snapshot)}.`;
    case 'breaksFloor':
      return `This takes ${a.name} below the ${formatMoney(a.minBalance)} you asked to keep.`;
    case 'insufficient':
      return `${a.name} only holds ${formatMoney(a.balance)}.`;
  }
}

function forcedCaution(quality: SourceQuality, account: Account): string {
  switch (quality) {
    case 'dipsIntoBills':
      return `Careful — this uses money already earmarked for a bill on ${account.name}.`;
    case 'breaksFloor':
      return `This takes ${account.name} below the ${formatMoney(account.minBalance)} floor you set.`;
    default:
      return '';
  }
}

/** Names the bills pinned to an account, so a warning says *which* bill. */
function billNames(accountId: string, obligations: Obligation[], snapshot: MoneySnapshot): string {
  const pinned = obligations
    .filter((o) => o.isActive && o.isOutflow && o.accountId === accountId)
    .filter((o) => {
      const due = o.nextOccurrenceOnOrAfter(snapshot.asOf);
      return due !== null && !isAfter(due, snapshot.horizon);
    })
    .sort((a, b) => b.amount - a.amount);

  if (pinned.length === 0) return 'money already committed here';

  const top = pinned[0];
  const due = top.nextOccurrenceOnOrAfter(snapshot.asOf);
  const extra = pinned.length > 1 ? ` and ${pinned.length - 1} more` : '';
  return `${top.name} (${formatMoney(top.amount)}${due === null ? '' : `, due ${dateLong(due)}`})${extra}`;
}

/** Plain-language reasons the other accounts were left alone. */
function rejections(candidates: PaymentCandidate[], chosenIds: string[]): string[] {
  const out: string[] = [];
  for (const c of candidates) {
    if (chosenIds.includes(c.account.id)) continue;
    if (c.caution === null) continue;
    out.push(`Not ${c.account.name} — ${lowerFirst(c.caution)}`);
  }
  return out.slice(0, 4);
}

function impactOf(snapshot: MoneySnapshot, amount: number): PaymentImpact {
  const usableAfter = snapshot.usableCash - amount;
  return new PaymentImpact(
    snapshot.safeToSpend - amount,
    snapshot.dailyBurn <= 0 ? null : usableAfter <= 0 ? 0 : usableAfter / snapshot.dailyBurn,
    snapshot.daysUntilIncome,
  );
}

/** Locked money is never offered automatically. */
const isUsable = (a: Account) => !a.isArchived && a.liquidity !== 'locked';

const liquidityRank = (l: Liquidity) => (l === 'liquid' ? 0 : l === 'reserved' ? 1 : 2);

const lowerFirst = (s: string) => (s.length === 0 ? s : s[0].toLowerCase() + s.slice(1));
