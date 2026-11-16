'use client';

/**
 * Dashboard widgets shared by Home and Insights — ports of
 * dashboard/presentation/widgets/*.dart.
 */

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { type MoneyAlert } from '@/lib/finance/alerts';
import { type MoneySnapshot } from '@/lib/finance/money-engine';
import { dayMonth, formatMoney, moneyDigits, monthShort } from '@/lib/format';
import { Icon } from './icons';
import { Card, Eyebrow, Glyph, Money, cx } from './ui';
import { hueFor } from '@/lib/present';

// --- Safe-to-spend hero -------------------------------------------------------

type HeroState = 'safe' | 'tight' | 'shortfall';

export function heroState(s: MoneySnapshot): HeroState {
  if (s.safeToSpend < 0) return 'shortfall';
  if (s.willFallShort) return 'tight';
  const days = s.daysUntilIncome;
  if (days !== null && days > 0 && s.dailyBurn > 0 && s.safeToSpend < s.dailyBurn * days * 1.15) {
    return 'tight';
  }
  return 'safe';
}

/** Spendable per day until payday; zero when there is nothing to spend. */
function perDay(s: MoneySnapshot): number {
  if (s.safeToSpend <= 0) return 0;
  const d = s.daysUntilIncome;
  return d === null || d <= 0 ? s.safeToSpend / 30 : s.safeToSpend / d;
}

function heroCaption(s: MoneySnapshot): string {
  if (s.safeToSpend < 0) {
    return `Your bills to ${dayMonth(s.horizon)} exceed what you hold. Something has to move or wait.`;
  }
  if (s.willFallShort) {
    return `At ${formatMoney(s.dailyBurn)} a day this runs out ${s.shortfallDays} days before money arrives.`;
  }
  const days = s.daysUntilIncome;
  if (days !== null) {
    return `before your next income on ${dayMonth(s.horizon)} · ${days} day${days === 1 ? '' : 's'}`;
  }
  if (s.runwayDays !== null) {
    return `over the next 30 days · about ${Math.floor(s.runwayDays)} days of runway at your current pace`;
  }
  return 'over the next 30 days. Log a few expenses and this starts telling you how long your money lasts.';
}

const HERO_STYLE: Record<HeroState, { box: string; eyebrow: string; dot: string }> = {
  safe: { box: 'bg-info-surface border-info-border text-info', eyebrow: 'Safe to spend', dot: 'bg-brand-ink' },
  tight: {
    box: 'bg-warning-surface border-warning-border text-warning',
    eyebrow: 'Tight before payday',
    dot: 'border-2 border-warning',
  },
  shortfall: {
    box: 'bg-expense-surface border-expense-border text-expense',
    eyebrow: 'Short before payday',
    dot: 'bg-expense',
  },
};

export function SafeToSpendHero({ s }: { s: MoneySnapshot }) {
  const router = useRouter();
  const state = heroState(s);
  const st = HERO_STYLE[state];
  return (
    <button
      type="button"
      onClick={() => router.push('/plan')}
      className={cx('block w-full rounded-3xl border p-5 text-left sm:p-6', st.box)}
      aria-label={`${st.eyebrow}: ${formatMoney(s.safeToSpend)}. Open commitments.`}
    >
      <div className="flex items-center gap-2">
        <span className={cx('h-[7px] w-[7px] rounded-full', st.dot)} />
        <Eyebrow className="text-current opacity-80">{st.eyebrow}</Eyebrow>
      </div>
      <div className="mt-3 flex items-baseline gap-2">
        <span className="text-lg font-medium opacity-70">{s.safeToSpend < 0 ? '-GHS' : 'GHS'}</span>
        <span className="tabular text-4xl font-semibold tracking-tight sm:text-5xl" data-testid="safe-to-spend">
          {moneyDigits(Math.abs(s.safeToSpend))}
        </span>
      </div>
      <p className="mt-2 text-sm opacity-90">{heroCaption(s)}</p>
      <div className="my-4 h-px bg-current opacity-15" />
      <div className="grid grid-cols-3 gap-2">
        {(
          [
            ['Total balance', s.totalBalance],
            ['Committed', s.committed],
            ['Per day', perDay(s)],
          ] as const
        ).map(([label, v]) => (
          <div key={label}>
            <div className="text-[11px] opacity-70">{label}</div>
            <div className="tabular mt-0.5 text-sm font-semibold text-ink sm:text-base">{formatMoney(v)}</div>
          </div>
        ))}
      </div>
    </button>
  );
}

// --- Alerts -------------------------------------------------------------------

const ALERT_STYLE = {
  critical: { box: 'bg-expense-surface border-expense-border text-expense', eyebrow: 'Not covered' },
  warning: { box: 'bg-warning-surface border-warning-border text-warning', eyebrow: 'Tight' },
  info: { box: 'bg-info-surface border-info-border text-info', eyebrow: 'For info' },
} as const;

export function AlertList({ alerts, heading }: { alerts: MoneyAlert[]; heading: string }) {
  const router = useRouter();
  const [expanded, setExpanded] = useState(false);
  if (alerts.length === 0) return null;
  const shown = expanded ? alerts : alerts.slice(0, 3);

  return (
    <section aria-label={heading}>
      <div className="mb-3 flex items-baseline justify-between">
        <h2 className="text-sm font-semibold">{heading}</h2>
        <Eyebrow>{alerts.length}</Eyebrow>
      </div>
      <ul className="space-y-2">
        {shown.map((a) => {
          const st = ALERT_STYLE[a.severity];
          const body = (
            <>
              <Eyebrow className="text-current opacity-75">{st.eyebrow}</Eyebrow>
              <p className="mt-1 font-medium">{a.title}</p>
              <p className="mt-0.5 text-sm opacity-90">{a.detail}</p>
            </>
          );
          return (
            <li key={a.id}>
              {a.actionRoute ? (
                <button
                  type="button"
                  onClick={() => router.push(a.actionRoute!)}
                  className={cx('block w-full rounded-2xl border px-4 py-3 text-left hover:opacity-95', st.box)}
                >
                  {body}
                  {a.actionLabel && <span className="mt-2 inline-block text-sm font-medium">{a.actionLabel} →</span>}
                </button>
              ) : (
                <div className={cx('rounded-2xl border px-4 py-3', st.box)}>{body}</div>
              )}
            </li>
          );
        })}
      </ul>
      {alerts.length > 3 && (
        <button
          type="button"
          onClick={() => setExpanded((e) => !e)}
          className="mt-2 text-sm font-medium text-brand-ink hover:underline"
        >
          {expanded ? 'Show less' : `${alerts.length - 3} more`}
        </button>
      )}
    </section>
  );
}

// --- Where your money sits ----------------------------------------------------

export function MoneyPlacement({ s }: { s: MoneySnapshot }) {
  const protectedAmt = s.floors + s.goalReserve + s.reserved + s.locked;
  const usable = s.usableCash > 0 ? s.usableCash : 0;
  const committed = Math.min(s.committed, usable);
  const segments = [
    { label: 'Liquid', value: usable - committed, color: 'bg-liquid' },
    { label: 'Committed', value: committed, color: 'bg-committed' },
    { label: 'Protected', value: protectedAmt, color: 'bg-protected' },
  ].filter((x) => x.value > 0.005);
  const total = segments.reduce((a, x) => a + x.value, 0);

  return (
    <Card>
      <h2 className="mb-3 text-sm font-semibold">Where your money sits</h2>
      {total <= 0 ? (
        <p className="text-sm text-ink-muted">
          No balances yet. Add what you actually hold in each account and this will show what is genuinely
          spendable.
        </p>
      ) : (
        <>
          <div className="flex h-2.5 gap-0.5 overflow-hidden rounded-full bg-track">
            {segments.map((x) => (
              <div key={x.label} className={x.color} style={{ width: `${(x.value / total) * 100}%` }} />
            ))}
          </div>
          <ul className="mt-3 space-y-2 text-sm">
            {segments.map((x) => (
              <li key={x.label} className="flex items-center gap-2">
                <span className={cx('h-2.5 w-2.5 rounded-full', x.color)} />
                <span className="flex-1 text-ink-body">{x.label}</span>
                <Money value={x.value} className="font-medium" />
              </li>
            ))}
          </ul>
          {s.safeToSpend < 0 && (
            <p className="mt-3 rounded-xl border border-expense-border bg-expense-surface px-3 py-2 text-sm text-expense">
              Bills exceed your spendable money by {formatMoney(-s.safeToSpend)}.
            </p>
          )}
        </>
      )}
    </Card>
  );
}

// --- Spending this month ------------------------------------------------------

export function SpendingMovement({ s }: { s: MoneySnapshot }) {
  const moved = s.categories.filter((c) => c.changeRatio !== null && Math.abs(c.changeRatio) >= 0.1);
  const rows = (moved.length > 0
    ? [...moved].sort((a, b) => Math.abs(b.changeRatio!) - Math.abs(a.changeRatio!))
    : s.categories
  ).slice(0, 3);
  const r = s.spendChangeRatio;
  const prevMonth = new Date(Date.UTC(s.asOf.getUTCFullYear(), s.asOf.getUTCMonth() - 1, 1));

  return (
    <Card>
      <div className="mb-3 flex items-baseline justify-between">
        <h2 className="text-sm font-semibold">Spending this month</h2>
        <Eyebrow>{r === null ? 'Last 30 days' : `vs ${monthShort(prevMonth)}`}</Eyebrow>
      </div>
      {s.spend30d <= 0 ? (
        <p className="text-sm text-ink-muted">No spending logged in the last 30 days.</p>
      ) : (
        <>
          <div className="flex items-baseline gap-3">
            <Money value={s.spend30d} className="text-2xl font-semibold" />
            {r !== null && (
              <span className={cx('text-sm', r > 0 ? 'text-expense' : 'text-income')}>
                {r > 0 ? '+' : '−'}
                {Math.abs(Math.round(r * 100))}%
              </span>
            )}
          </div>
          <ul className="mt-4 space-y-3">
            {rows.map((c) => (
              <li key={c.category} className="flex items-center gap-3 text-sm">
                <Glyph name={c.category} hue={hueFor(c.category)} size={28} />
                <span className="flex-1 truncate">{c.category}</span>
                {c.changeRatio !== null && Math.abs(c.changeRatio) >= 0.1 ? (
                  <span className={cx('font-medium', c.changeRatio > 0 ? 'text-expense' : 'text-income')}>
                    {c.changeRatio > 0 ? '+' : '−'}
                    {Math.abs(Math.round(c.changeRatio * 100))}%
                  </span>
                ) : (
                  <Money value={c.amount} className="font-medium" />
                )}
              </li>
            ))}
          </ul>
        </>
      )}
    </Card>
  );
}

export function PayButton({ secondary }: { secondary?: boolean }) {
  return (
    <Link
      href="/pay"
      className={cx(
        'flex h-12 items-center justify-center gap-2 rounded-2xl text-sm font-medium',
        secondary
          ? 'border border-outline bg-card text-ink hover:bg-recessed'
          : 'bg-brand text-on-brand hover:bg-brand-pressed',
      )}
    >
      <Icon name="pay" width={18} height={18} /> I need to pay someone — where from?
    </Link>
  );
}
