/** Port of ask_ai_tab.dart `_suggestionsFor` and the thinking-indicator labels. */

import { type Account } from '../domain/account';
import { type Goal } from '../domain/goal';
import { type Obligation } from '../domain/obligation';
import { CATEGORY_SPIKE_FLOOR, CATEGORY_SPIKE_RATIO, type MoneyAlert } from '../finance/alerts';
import { type MoneySnapshot } from '../finance/money-engine';

export function suggestionsFor(
  s: MoneySnapshot,
  alerts: MoneyAlert[],
  goals: Goal[],
  obligations: Obligation[],
  accounts: Account[],
): string[] {
  const out: string[] = [];
  if (s.willFallShort) out.push('Why am I running short before payday, and what do I cut?');

  const spike = s.categories.find(
    (c) => (c.changeRatio ?? 0) >= CATEGORY_SPIKE_RATIO && c.delta >= CATEGORY_SPIKE_FLOOR,
  );
  if (spike) out.push(`Why is ${spike.category} up this month?`);

  if (s.daysUntilIncome === null) out.push('Help me record my salary and bills.');
  else if (s.safeToSpend > 0) out.push('How much can I spend a day until my next income?');

  if (accounts.length > 1 && s.liquid > 0) {
    const amount = s.safeToSpend > 1000 ? 500 : s.safeToSpend > 200 ? 100 : 50;
    out.push(`I need to send GHS ${amount} — which account should it come from?`);
  }

  if (alerts.some((a) => a.id.startsWith('bill.uncovered.'))) out.push('Sort out the bill I cannot cover.');
  else if (obligations.some((o) => o.isActive && o.isOutflow)) {
    out.push('What is leaving my accounts in the next two weeks?');
  }

  const goal = goals.find((g) => g.isActive && !g.isComplete);
  if (goal) out.push(`Am I on track for ${goal.name}?`);

  if (s.spend30d > 0) out.push('Where is my money actually going?');
  return out.slice(0, 4);
}

export const TOOL_LABELS: Record<string, string> = {
  get_position: 'Checking your position',
  get_alerts: 'Looking for problems',
  list_accounts: 'Reading your accounts',
  list_commitments: 'Reading your bills and goals',
  plan_payment: 'Working out where to pay from',
  get_spending: 'Adding up your spending',
  list_transactions: 'Looking through your transactions',
  propose_transfer: 'Preparing a transfer for you to approve',
  propose_commitment: 'Preparing a record for you to approve',
};
