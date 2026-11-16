'use client';

/**
 * Daily tips — a port of daily_tip_service.dart and OpenAIService.tipBatch,
 * except the request goes through the `coach` Edge Function instead of a key
 * held on the device. A batch of five is cached in localStorage and one is
 * shown per day.
 */

import { diffDays, parseDate, toIsoDate, today } from '../dates';
import { kindLabel, liquidityLabel, type Account } from '../domain/account';
import { type Goal } from '../domain/goal';
import { cadenceLabel, type Obligation } from '../domain/obligation';
import { type Txn } from '../domain/transaction';
import { type MoneySnapshot } from '../finance/money-engine';
import { EdgeFunctionTransport } from './transport';

export const TIP_BATCH_SIZE = 5;
const STORE_KEY = 'tip_batch_v1';

interface TipBatch {
  userId: string;
  tips: string[];
  startDate: string; // YYYY-MM-DD
}

export function tipForToday(b: TipBatch): string | null {
  const diff = diffDays(today(), parseDate(b.startDate));
  return diff < 0 || diff >= b.tips.length ? null : b.tips[diff];
}

export function cachedBatch(userId: string): TipBatch | null {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    if (!raw) return null;
    const b = JSON.parse(raw) as TipBatch;
    // Per user, so a shared browser never shows one person's tips to another.
    return b.userId === userId && Array.isArray(b.tips) ? b : null;
  } catch {
    return null;
  }
}

export function clearTips() {
  try {
    localStorage.removeItem(STORE_KEY);
  } catch {}
}

export async function generateBatch(input: {
  userId: string;
  snapshot: MoneySnapshot;
  accounts: Account[];
  txns: Txn[];
  obligations: Obligation[];
  goals: Goal[];
}): Promise<TipBatch> {
  const context = buildContext(input);
  const n = TIP_BATCH_SIZE;
  const prompt =
    input.txns.length > 0
      ? `Generate ${n} distinct, short personal-finance tips for this user. ` +
        'Each tip: 2 sentences max, 50 words max, plain text, no markdown, no greeting. ' +
        'Reference real numbers from their data (in GHS) where useful. Each tip must ' +
        'cover a different angle (e.g. spending category, savings, emergency fund, ' +
        'budgeting habit, mindset).\n\nReturn ONLY the tips, one per line, prefixed ' +
        `with "1." through "${n}." (e.g. "1. ..."). No extra commentary.\n\nContext:\n${context}`
      : `Generate ${n} distinct short personal-finance tips for a beginner with no ` +
        'transactions yet. Each tip: 2 sentences max, 50 words max, plain text, no ' +
        'markdown, no greeting. Topics should vary (e.g. tracking habit, saving, ' +
        'budgeting, debt, mindset).\n\nReturn ONLY the tips, one per line, prefixed ' +
        `with "1." through "${n}." (e.g. "1. ...").`;

  const message = await new EdgeFunctionTransport().complete(
    [
      {
        role: 'system',
        content:
          'You are a concise personal-finance coach for a user in Ghana (currency GHS). ' +
          'Output plain text only. No markdown.',
      },
      { role: 'user', content: prompt },
    ],
    null,
    { temperature: 0.85, max_tokens: 800 },
  );

  const tips = parseTips(String(message.content ?? ''));
  if (tips.length === 0) throw new Error('Could not read the tips the coach sent back.');

  const batch: TipBatch = { userId: input.userId, tips, startDate: toIsoDate(today()) };
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(batch));
  } catch {}
  return batch;
}

export function parseTips(raw: string): string[] {
  const tips: string[] = [];
  for (const line of raw.split('\n')) {
    const t = line.trim();
    if (!t) continue;
    const m = /^\d+[.)]\s*(.+)$/.exec(t);
    if (m) tips.push(m[1].trim());
    else if (tips.length > 0) tips[tips.length - 1] = `${tips[tips.length - 1]} ${t}`;
  }
  return tips;
}

/** Same context the app builds — every figure already computed. */
function buildContext({
  snapshot: s,
  txns,
  obligations,
  goals,
}: {
  snapshot: MoneySnapshot;
  txns: Txn[];
  obligations: Obligation[];
  goals: Goal[];
}): string {
  const ctx = {
    currency: 'GHS',
    today: toIsoDate(s.asOf),
    position: {
      total_balance: s.totalBalance,
      spendable_now: s.liquid,
      reserved: s.reserved,
      locked: s.locked,
      minimum_balances_held: s.floors,
      held_for_goals: s.goalReserve,
      [`bills_due_before_${toIsoDate(s.horizon)}`]: s.committed,
      safe_to_spend: s.safeToSpend,
    },
    pace: {
      average_spend_per_day: s.dailyBurn,
      days_of_cash_left: s.runwayDays,
      days_until_next_income: s.daysUntilIncome,
      will_run_short_before_income: s.willFallShort,
      ...(s.willFallShort ? { short_by_days: s.shortfallDays } : {}),
    },
    accounts: s.standings.map((st) => ({
      name: st.account.name,
      kind: kindLabel(st.account.kind),
      liquidity: liquidityLabel(st.account.liquidity),
      balance: st.account.balance,
      keep_at_least: st.account.minBalance,
      free_to_move: st.freeToMove,
      bills_pinned_here: st.committed,
      ...(st.account.purpose ? { purpose: st.account.purpose } : {}),
      ...(st.isBelowFloor ? { warning: 'below its minimum balance' } : {}),
    })),
    upcoming: obligations
      .filter((o) => o.isActive)
      .map((o) => ({
        name: o.name,
        direction: o.isOutflow ? 'bill' : 'income',
        amount: o.amount,
        every: cadenceLabel(o.cadence),
        next: toIsoDate(o.nextDue),
      })),
    goals: goals
      .filter((g) => g.isActive)
      .map((g) => ({
        name: g.name,
        target: g.targetAmount,
        set_aside: g.savedAmount,
        ...(g.targetDate ? { by: toIsoDate(g.targetDate) } : {}),
      })),
    last_30_days: { income: s.income30d, spending: s.spend30d, net: s.income30d - s.spend30d },
    spending_by_category_30d: s.categories.slice(0, 8).map((c) => ({
      category: c.category,
      amount: c.amount,
      previous_30d: c.previousAmount,
      ...(c.changeRatio !== null ? { change_pct: Math.round(c.changeRatio * 100) } : {}),
    })),
    recent_transactions: txns
      .filter((t) => t.isRealMoneyMovement)
      .slice(0, 10)
      .map((t) => ({
        date: toIsoDate(t.date),
        type: t.type,
        amount: t.amount,
        category: t.category,
        ...(t.description ? { note: t.description } : {}),
      })),
  };
  return JSON.stringify(ctx, null, 2);
}
