/**
 * Port of insights/data/coach_tools.dart.
 *
 * Reading tools run straight against the money engine, so every number the
 * model quotes was computed and tested. The two writing tools do not write:
 * they return a proposal the user has to tap.
 */

import { addDays, isBefore, toIsoDate, tryParseDate } from '../dates';
import { kindLabel, liquidityLabel, type Account } from '../domain/account';
import { type Goal } from '../domain/goal';
import { cadenceFromValue, cadenceLabel, type Obligation } from '../domain/obligation';
import { type Txn } from '../domain/transaction';
import { buildAlerts } from '../finance/alerts';
import { type MoneySnapshot } from '../finance/money-engine';
import { planPayment } from '../finance/payment-planner';
import { dateLong, formatMoney } from '../format';
import { type CoachAction } from './types';

export interface ToolResult {
  content: string;
  action?: CoachAction | null;
}

/** Everything the tools need. Assembled once per turn. */
export class CoachContext {
  constructor(
    readonly snapshot: MoneySnapshot,
    readonly accounts: Account[],
    readonly txns: Txn[],
    readonly obligations: Obligation[],
    readonly goals: Goal[],
  ) {}

  /**
   * Resolves whatever the user or model called an account: exact, then
   * substring, then run-together word prefixes ("Momo" -> "Mobile Money").
   */
  accountByName(name: string): Account | null {
    const needle = name.trim().toLowerCase();
    if (!needle) return null;

    for (const a of this.accounts) if (a.name.toLowerCase() === needle) return a;
    for (const a of this.accounts) {
      const c = a.name.toLowerCase();
      if (c.includes(needle) || needle.includes(c)) return a;
    }
    for (const a of this.accounts) {
      const c = a.name.toLowerCase();
      if (wordPrefixMatch(needle, c) || wordPrefixMatch(c, needle)) return a;
    }
    return null;
  }
}

/** Tool definitions in OpenAI function-calling shape — identical to the app. */
export const COACH_TOOLS = [
  {
    type: 'function',
    function: {
      name: 'get_position',
      description:
        "The user's current money position: total balance, what is spendable " +
        'versus reserved or locked, bills already committed, safe-to-spend, ' +
        'daily spending rate, days of cash left and days until income. ' +
        'Call this before answering anything about affordability.',
      parameters: { type: 'object', properties: {} },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_alerts',
      description:
        'Problems the app has already detected — running short before payday, ' +
        'accounts below their floor, bills an account cannot cover, spending ' +
        'spikes. These are computed, not guessed.',
      parameters: { type: 'object', properties: {} },
    },
  },
  {
    type: 'function',
    function: {
      name: 'list_accounts',
      description:
        'Every account with its balance, kind, whether it is spendable, its ' +
        'minimum balance, what it is for, and how much is genuinely free to ' +
        'move out of it.',
      parameters: { type: 'object', properties: {} },
    },
  },
  {
    type: 'function',
    function: {
      name: 'list_commitments',
      description:
        'Recurring bills, expected income, and savings goals, with when each next lands.',
      parameters: { type: 'object', properties: {} },
    },
  },
  {
    type: 'function',
    function: {
      name: 'plan_payment',
      description:
        'Work out which account a payment should come from. Returns the ' +
        'recommendation, why every other account was rejected, any transfers ' +
        'needed first, and what the payment leaves behind. Always use this ' +
        'rather than reasoning about accounts yourself.',
      parameters: {
        type: 'object',
        properties: {
          amount: { type: 'number', description: 'Amount to pay, in GHS.' },
          must_leave_account: {
            type: 'string',
            description:
              'Optional account name the money has to physically leave from, ' +
              'for example when sending over mobile money.',
          },
        },
        required: ['amount'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_spending',
      description:
        'Spending by category over a window, with how each category moved ' +
        'against the previous window of the same length.',
      parameters: {
        type: 'object',
        properties: {
          days: { type: 'integer', description: 'Window length in days. Defaults to 30.' },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'list_transactions',
      description:
        'Recent individual transactions, most recent first. Use when the user ' +
        'asks about specific spending rather than totals.',
      parameters: {
        type: 'object',
        properties: {
          days: { type: 'integer', description: 'How far back. Default 30.' },
          category: { type: 'string', description: 'Optional category filter.' },
          limit: { type: 'integer', description: 'Max rows. Default 20.' },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'propose_transfer',
      description:
        'Offer the user a transfer between their own accounts. This does NOT ' +
        'move any money — it shows them a card they can approve. Use it ' +
        'whenever the right answer is "move money from here to there".',
      parameters: {
        type: 'object',
        properties: {
          from_account: { type: 'string' },
          to_account: { type: 'string' },
          amount: { type: 'number' },
          reason: { type: 'string', description: 'One short sentence on why, shown on the card.' },
        },
        required: ['from_account', 'to_account', 'amount', 'reason'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'propose_commitment',
      description:
        'Offer to record a recurring bill or expected income the user has ' +
        'mentioned but never logged. Does NOT save anything — the user has ' +
        'to approve the card.',
      parameters: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          amount: { type: 'number' },
          direction: { type: 'string', enum: ['bill', 'income'] },
          cadence: {
            type: 'string',
            enum: ['once', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'],
          },
          next_due: { type: 'string', description: 'Date it next lands, as YYYY-MM-DD.' },
          account: {
            type: 'string',
            description: 'Optional account it is paid from or arrives into.',
          },
        },
        required: ['name', 'amount', 'direction', 'cadence', 'next_due'],
      },
    },
  },
];

type Args = Record<string, unknown>;

/** Runs one tool call. Never throws: failures go back to the model as text. */
export function runCoachTool(name: string, args: Args, c: CoachContext): ToolResult {
  try {
    switch (name) {
      case 'get_position':
        return getPosition(c);
      case 'get_alerts':
        return getAlerts(c);
      case 'list_accounts':
        return listAccounts(c);
      case 'list_commitments':
        return listCommitments(c);
      case 'plan_payment':
        return planPaymentTool(args, c);
      case 'get_spending':
        return getSpending(args, c);
      case 'list_transactions':
        return listTransactions(args, c);
      case 'propose_transfer':
        return proposeTransfer(args, c);
      case 'propose_commitment':
        return proposeCommitment(args, c);
      default:
        return { content: `There is no tool called "${name}".` };
    }
  } catch (e) {
    return { content: `That tool failed: ${e instanceof Error ? e.message : String(e)}` };
  }
}

function getPosition(c: CoachContext): ToolResult {
  const s = c.snapshot;
  const lines = [
    `Currency: GHS. Today: ${dateLong(s.asOf)}.`,
    `Total balance: ${formatMoney(s.totalBalance)}.`,
    `Spendable accounts hold ${formatMoney(s.liquid)}; ` +
      `${formatMoney(s.reserved)} is reserved and ${formatMoney(s.locked)} is locked.`,
    `Minimum balances held back: ${formatMoney(s.floors)}. ` +
      `Held for goals: ${formatMoney(s.goalReserve)}.`,
    `Bills due before ${dateLong(s.horizon)}: ${formatMoney(s.committed)}.`,
    `SAFE TO SPEND: ${formatMoney(s.safeToSpend)}.`,
    `Average spending: ${formatMoney(s.dailyBurn)} per day.`,
  ];
  if (s.runwayDays !== null) lines.push(`Cash lasts about ${Math.floor(s.runwayDays)} days at that rate.`);
  lines.push(
    s.daysUntilIncome !== null
      ? `Next income arrives in ${s.daysUntilIncome} days.`
      : 'No expected income is recorded, so runway cannot be judged against payday.',
  );
  if (s.willFallShort) {
    lines.push(`WARNING: money runs out ${s.shortfallDays} days before income arrives.`);
  }
  lines.push(
    `Last 30 days: ${formatMoney(s.income30d)} in, ${formatMoney(s.spend30d)} out ` +
      '(transfers between own accounts excluded).',
  );
  return { content: lines.join('\n') };
}

function getAlerts(c: CoachContext): ToolResult {
  const alerts = buildAlerts({ snapshot: c.snapshot, obligations: c.obligations, goals: c.goals });
  if (alerts.length === 0) return { content: 'No problems detected right now.' };
  return {
    content: alerts.map((a) => `[${a.severity.toUpperCase()}] ${a.title} — ${a.detail}`).join('\n'),
  };
}

function listAccounts(c: CoachContext): ToolResult {
  if (c.snapshot.standings.length === 0) return { content: 'The user has no accounts set up.' };
  const lines = c.snapshot.standings.map((st) => {
    const a = st.account;
    return [
      a.name,
      `${kindLabel(a.kind)}, ${liquidityLabel(a.liquidity).toLowerCase()}`,
      `balance ${formatMoney(a.balance)}`,
      ...(a.minBalance > 0 ? [`must keep ${formatMoney(a.minBalance)}`] : []),
      ...(st.committed > 0 ? [`bills pinned here ${formatMoney(st.committed)}`] : []),
      `free to move ${formatMoney(st.freeToMove)}`,
      ...(a.purpose ? [`purpose: ${a.purpose}`] : []),
      ...(st.isBelowFloor ? ['WARNING: below its minimum balance'] : []),
    ].join(' · ');
  });
  return { content: lines.join('\n') };
}

function listCommitments(c: CoachContext): ToolResult {
  const out: string[] = [];
  for (const o of c.obligations.filter((o) => o.isActive)) {
    const next = o.nextOccurrenceOnOrAfter(c.snapshot.asOf);
    out.push(
      [
        o.isOutflow ? 'BILL' : 'INCOME',
        o.name,
        formatMoney(o.amount),
        cadenceLabel(o.cadence).toLowerCase(),
        ...(next ? [`next ${dateLong(next)}`] : []),
      ].join(' · '),
    );
  }
  for (const g of c.goals.filter((g) => g.isActive)) {
    out.push(
      `GOAL · ${g.name} · ${formatMoney(g.savedAmount)} saved of ${formatMoney(g.targetAmount)}` +
        (g.targetDate ? ` · by ${dateLong(g.targetDate)}` : ''),
    );
  }
  if (out.length === 0) {
    return {
      content:
        'Nothing recorded. The user has not told the app about any bills, ' +
        'income or goals — say so, because it limits what can be worked out.',
    };
  }
  return { content: out.join('\n') };
}

function planPaymentTool(args: Args, c: CoachContext): ToolResult {
  const amount = toNumber(args.amount);
  if (amount === null || amount <= 0) return { content: 'Need a positive amount to plan a payment.' };

  let forcedId: string | null = null;
  const forcedName = typeof args.must_leave_account === 'string' ? args.must_leave_account : null;
  if (forcedName && forcedName.trim()) {
    const match = c.accountByName(forcedName);
    if (!match) {
      return {
        content:
          `There is no account called "${forcedName}". Accounts are: ` +
          `${c.accounts.map((a) => a.name).join(', ')}.`,
      };
    }
    forcedId = match.id;
  }

  const plan = planPayment({
    amount,
    snapshot: c.snapshot,
    obligations: c.obligations,
    payFromAccountId: forcedId,
  });

  const lines = [plan.headline];
  if (!plan.isPossible) lines.push('This payment is not currently possible.');
  for (const t of plan.transfers) {
    lines.push(`Transfer first: ${formatMoney(t.amount)} from ${t.from.name} to ${t.to.name}.`);
  }
  for (const s of plan.sources) {
    lines.push(`Take ${formatMoney(s.amount)} from ${s.account.name}${s.caution ? ` — ${s.caution}` : ''}`);
  }
  lines.push(...plan.reasoning);
  if (plan.isPossible) {
    const r = plan.impact.runwayDaysAfter;
    lines.push(
      `After this: ${formatMoney(plan.impact.safeToSpendAfter)} spendable` +
        (r === null ? '' : `, about ${Math.floor(r)} days of cash`) +
        (plan.impact.causesShortfall
          ? '. WARNING: this causes a shortfall before income arrives.'
          : '.'),
    );
  }
  return { content: lines.join('\n') };
}

function getSpending(args: Args, c: CoachContext): ToolResult {
  const days = toInt(args.days) ?? 30;
  const asOf = c.snapshot.asOf;
  const start = addDays(asOf, -days);
  const prevStart = addDays(asOf, -days * 2);

  const current = new Map<string, number>();
  const previous = new Map<string, number>();
  for (const t of c.txns) {
    if (!t.isSpending) continue;
    if (!isBefore(t.date, start) && t.date.getTime() <= asOf.getTime()) {
      current.set(t.category, (current.get(t.category) ?? 0) + t.amount);
    } else if (!isBefore(t.date, prevStart) && isBefore(t.date, start)) {
      previous.set(t.category, (previous.get(t.category) ?? 0) + t.amount);
    }
  }

  if (current.size === 0) return { content: `No spending recorded in the last ${days} days.` };

  const entries = [...current.entries()].sort((a, b) => b[1] - a[1]);
  const total = entries.reduce((s, [, v]) => s + v, 0);
  const lines = [`Total spending over ${days} days: ${formatMoney(total)}.`];
  for (const [k, v] of entries) {
    const before = previous.get(k) ?? 0;
    const change =
      before <= 0
        ? 'no comparison available'
        : `${Math.round(((v - before) / before) * 100)}% versus ${formatMoney(before)} the ${days} days before`;
    lines.push(`${k}: ${formatMoney(v)} (${change})`);
  }
  return { content: lines.join('\n') };
}

function listTransactions(args: Args, c: CoachContext): ToolResult {
  const days = toInt(args.days) ?? 30;
  const limit = Math.min(50, Math.max(1, toInt(args.limit) ?? 20));
  const category = typeof args.category === 'string' ? args.category.trim().toLowerCase() : null;
  const start = addDays(c.snapshot.asOf, -days);
  const names = new Map(c.accounts.map((a) => [a.id, a.name]));

  const rows = c.txns
    .filter((t) => t.isRealMoneyMovement)
    .filter((t) => !isBefore(t.date, start))
    .filter((t) => category === null || t.category.toLowerCase().includes(category))
    .slice(0, limit)
    .map(
      (t) =>
        `${toIsoDate(t.date)} · ${t.type} · ${formatMoney(t.amount)} · ${t.category} · ` +
        `${names.get(t.accountId) ?? 'unknown account'}` +
        (t.description ? ` · ${t.description}` : ''),
    );

  if (rows.length === 0) return { content: `No matching transactions in the last ${days} days.` };
  return { content: rows.join('\n') };
}

function proposeTransfer(args: Args, c: CoachContext): ToolResult {
  const amount = toNumber(args.amount);
  if (amount === null || amount <= 0) return { content: 'A transfer needs a positive amount.' };

  const from = c.accountByName(typeof args.from_account === 'string' ? args.from_account : '');
  const to = c.accountByName(typeof args.to_account === 'string' ? args.to_account : '');
  const known = c.accounts.map((a) => a.name).join(', ');

  if (!from) return { content: `No account matches "${args.from_account}". Accounts are: ${known}.` };
  if (!to) return { content: `No account matches "${args.to_account}". Accounts are: ${known}.` };
  if (from.id === to.id) return { content: 'A transfer needs two different accounts.' };
  if (from.balance < amount) {
    return {
      content: `${from.name} only holds ${formatMoney(from.balance)}, so it cannot send ${formatMoney(amount)}.`,
    };
  }

  const reason = typeof args.reason === 'string' ? args.reason.trim() : '';
  return {
    content:
      `Offered the user a transfer of ${formatMoney(amount)} from ${from.name} ` +
      `to ${to.name}. It has NOT happened — they must approve it. Tell them ` +
      'briefly what it does; do not claim it is done.',
    action: {
      type: 'transfer',
      fromAccountId: from.id,
      fromAccountName: from.name,
      toAccountId: to.id,
      toAccountName: to.name,
      amount,
      reason: reason || 'Suggested by your coach',
    },
  };
}

function proposeCommitment(args: Args, c: CoachContext): ToolResult {
  const amount = toNumber(args.amount);
  if (amount === null || amount <= 0) return { content: 'A commitment needs a positive amount.' };

  const name = typeof args.name === 'string' ? args.name.trim() : '';
  if (!name) return { content: 'A commitment needs a name.' };

  const nextDue = tryParseDate(typeof args.next_due === 'string' ? args.next_due : null);
  if (!nextDue) return { content: 'next_due must be a date like 2026-08-01.' };

  const direction = args.direction === 'income' ? 'in' : 'out';
  const cadence = cadenceFromValue(typeof args.cadence === 'string' ? args.cadence : 'monthly');

  const accountName = typeof args.account === 'string' ? args.account.trim() : '';
  const account = accountName ? c.accountByName(accountName) : null;

  return {
    content:
      `Offered the user a ${direction === 'out' ? 'bill' : 'income'} record: ${name}, ` +
      `${formatMoney(amount)}, ${cadenceLabel(cadence).toLowerCase()}, next ` +
      `${dateLong(nextDue)}. It has NOT been saved — they must approve it.`,
    action: {
      type: 'commitment',
      name,
      amount,
      direction,
      cadence,
      nextDue,
      accountId: account?.id ?? null,
      accountName: account?.name ?? null,
    },
  };
}

/**
 * Whether `needle` is `name`'s words run together by their prefixes ("momo"
 * for "mobile money"). Every word must contribute at least two characters and
 * the needle must be fully consumed.
 */
function wordPrefixMatch(needle: string, name: string): boolean {
  if (needle.length < 3) return false;
  const words = name.split(/[^a-z0-9]+/).filter(Boolean);
  if (words.length < 2) return false;

  let rest = needle;
  for (const word of words) {
    let taken = 0;
    while (taken < word.length && taken < rest.length && rest[taken] === word[taken]) taken++;
    if (taken < 2) return false;
    rest = rest.slice(taken);
  }
  return rest.length === 0;
}

function toNumber(v: unknown): number | null {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function toInt(v: unknown): number | null {
  const n = toNumber(v);
  return n === null ? null : Math.trunc(n);
}
