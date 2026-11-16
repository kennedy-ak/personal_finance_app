'use client';

import { useMemo, useState } from 'react';
import { Card, Empty, ErrorNote, Eyebrow, Glyph, Loading, Money, Tabs, cx } from '@/components/ui';
import { useAccounts, useTodayIso, useTransactions } from '@/lib/data/hooks';
import { addDays, isAfter, parseDate, toIsoDate, type DateOnly } from '@/lib/dates';
import { type Txn } from '@/lib/domain/transaction';
import {
  byAccount,
  byCategory,
  dailySpend,
  lastSixMonths,
  reading,
  statsBetween,
  weekStart,
} from '@/lib/finance/reports';
import { dayMonth, formatMoney, monthShort } from '@/lib/format';
import { hueFor, plural } from '@/lib/present';

type Tab = 'week' | 'trends' | 'detailed';
const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const CHART = ['#0E7C66', '#F59E0B', '#8B5CF6', '#EF4444', '#3B82F6', '#EC4899', '#14B8A6', '#EAB308', '#6366F1', '#10B981', '#F97316', '#06B6D4'];

/** Port of reports/presentation/reports_screen.dart. */
export default function ReportsPage() {
  const { data, isLoading, error } = useTransactions();
  const todayIso = useTodayIso();
  const [tab, setTab] = useState<Tab>('week');

  if (isLoading || !todayIso) return <Loading />;
  if (error) return <ErrorNote error={error} />;
  const txns = data ?? [];
  const now = parseDate(todayIso);

  return (
    <>
      <h1 className="mb-4 text-2xl font-semibold tracking-tight">Reports</h1>
      <Tabs<Tab>
        label="Report"
        value={tab}
        onChange={setTab}
        options={[
          { value: 'week', label: 'This week' },
          { value: 'trends', label: 'Trends' },
          { value: 'detailed', label: 'Detailed' },
        ]}
      />
      {tab === 'week' && <ThisWeek txns={txns} now={now} />}
      {tab === 'trends' && <Trends txns={txns} now={now} />}
      {tab === 'detailed' && <Detailed txns={txns} now={now} />}
    </>
  );
}

function ThisWeek({ txns, now }: { txns: Txn[]; now: DateOnly }) {
  const monday = weekStart(now);
  const s = statsBetween(txns, monday, addDays(monday, 7));
  const days = dailySpend(txns, monday);
  const peak = Math.max(...days);
  const todayIdx = Math.round((now.getTime() - monday.getTime()) / 86_400_000);
  const net = s.income - s.expense;

  return (
    <div className="space-y-4">
      <div
        className={cx(
          'rounded-3xl border p-6',
          net >= 0 ? 'border-income-border bg-income-surface text-income' : 'border-expense-border bg-expense-surface text-expense',
        )}
      >
        <Eyebrow className="text-current opacity-80">Net this week</Eyebrow>
        <Money value={net} className="mt-2 block text-4xl font-semibold" />
        <p className="mt-1 text-sm opacity-90">
          {dayMonth(monday)} – {dayMonth(addDays(monday, 6))} · {plural(s.count, 'transaction')}
        </p>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <Card>
          <Eyebrow>Income</Eyebrow>
          <Money value={s.income} tone="income" className="mt-1 block text-2xl font-semibold" />
        </Card>
        <Card>
          <Eyebrow>Expense</Eyebrow>
          <Money value={s.expense} tone="expense" className="mt-1 block text-2xl font-semibold" />
        </Card>
      </div>
      <Card>
        <div className="mb-4 flex items-baseline justify-between">
          <h2 className="text-sm font-semibold">Daily spend</h2>
          <Eyebrow>{peak > 0 ? `Peak ${formatMoney(peak)}` : 'Nothing spent'}</Eyebrow>
        </div>
        <div className="flex h-40 items-end gap-2">
          {days.map((v, i) => (
            <div key={i} className="flex h-full flex-1 flex-col items-center justify-end gap-1.5" title={`${DAYS[i]} · ${formatMoney(v)}`}>
              <div
                className={cx('w-full rounded-t-md', v === peak && v > 0 ? 'bg-brand-ink' : 'bg-outline')}
                style={{ height: `${peak > 0 ? Math.max(2, (v / peak) * 100) : 2}%` }}
                aria-label={`${DAYS[i]} ${formatMoney(v)}`}
                role="img"
              />
              <span className={cx('text-[11px]', i === todayIdx ? 'font-bold text-ink' : 'text-ink-muted')}>{DAYS[i]}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}

function Trends({ txns, now }: { txns: Txn[]; now: DateOnly }) {
  const months = useMemo(() => lastSixMonths(txns, now), [txns, now]);
  const current = months[months.length - 1];
  const previous = months[months.length - 2];
  const withSpend = months.filter((m) => m.expense > 0);
  const avgSpend = withSpend.length ? withSpend.reduce((s, m) => s + m.expense, 0) / withSpend.length : 0;
  const best = months.reduce((a, b) => (b.net > a.net ? b : a));
  const peak = Math.max(0, ...months.map((m) => Math.abs(m.net)));

  return (
    <div className="space-y-4">
      <Card>
        <h2 className="text-sm font-semibold">Net by month</h2>
        <p className="mt-1 text-xs text-ink-muted">Six months. Bars below the line are months you spent more than you earned.</p>
        <div className="mt-5 flex h-44 gap-2.5">
          {months.map((m, i) => {
            const frac = peak > 0 ? Math.abs(m.net) / peak : 0;
            const latest = i === months.length - 1;
            const color = m.net >= 0 ? 'bg-income' : 'bg-expense';
            return (
              <div key={i} className="flex flex-1 flex-col" title={`${monthShort(m.month)} · ${formatMoney(m.net)}`}>
                <div className="flex flex-1 items-end">
                  {m.net >= 0 && (
                    <div className={cx('w-full rounded-t-md', color, !latest && 'opacity-50')} style={{ height: `${Math.max(2, frac * 100)}%` }} />
                  )}
                </div>
                <div className="h-px bg-outline" />
                <div className="flex flex-1 items-start">
                  {m.net < 0 && (
                    <div className={cx('w-full rounded-b-md', color, !latest && 'opacity-50')} style={{ height: `${Math.max(2, frac * 100)}%` }} />
                  )}
                </div>
                <span className={cx('mt-1.5 text-center text-[11px]', latest ? 'text-ink' : 'text-ink-muted')}>{monthShort(m.month)}</span>
              </div>
            );
          })}
        </div>
      </Card>
      <Card>
        <h2 className="mb-3 text-sm font-semibold">Month over month</h2>
        <TrendRow
          label={`${monthShort(current.month)} net`}
          value={current.net}
          delta={previous.net === 0 ? null : (current.net - previous.net) / Math.abs(previous.net)}
          upIsGood
        />
        <TrendRow label="Average spend" value={avgSpend} delta={avgSpend <= 0 ? null : (current.expense - avgSpend) / avgSpend} />
        <TrendRow label="Best month" value={best.net} note={monthShort(best.month)} />
      </Card>
      <div className="rounded-2xl border border-accent-border bg-accent-surface p-4 text-accent">
        <Eyebrow className="text-current">Reading</Eyebrow>
        <p className="mt-2 text-sm leading-relaxed">{reading(months)}</p>
      </div>
    </div>
  );
}

function TrendRow({
  label,
  value,
  delta,
  note,
  upIsGood = false,
}: {
  label: string;
  value: number;
  delta?: number | null;
  note?: string;
  upIsGood?: boolean;
}) {
  const good = delta == null ? true : delta >= 0 === upIsGood;
  return (
    <div className="flex items-center gap-3 py-1.5 text-sm">
      <span className="flex-1 text-ink-body">{label}</span>
      <Money value={value} className="font-semibold" />
      <span
        className={cx('w-14 text-right text-xs font-medium', delta == null ? 'text-ink-muted' : good ? 'text-income' : 'text-expense')}
      >
        {delta != null ? `${delta >= 0 ? '+' : '−'}${Math.round(Math.abs(delta) * 100)}%` : (note ?? '')}
      </span>
    </div>
  );
}

function Detailed({ txns, now }: { txns: Txn[]; now: DateOnly }) {
  const accounts = useAccounts();
  const names = new Map((accounts.data ?? []).map((a) => [a.id, a.name]));
  const [monday, setMonday] = useState(() => weekStart(now));
  const end = addDays(monday, 7);
  const canNext = !isAfter(addDays(monday, 7), now);
  const s = statsBetween(txns, monday, end);
  const cats = byCategory(txns, monday, end);
  const catTotal = cats.reduce((a, c) => a + c.value, 0);
  const accts = byAccount(txns, monday, end);
  const weekNo = isoWeek(monday);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between rounded-2xl border border-hairline bg-card px-2 py-2">
        <button type="button" onClick={() => setMonday(addDays(monday, -7))} aria-label="Previous week" className="rounded-lg px-3 py-2 hover:bg-recessed">
          ‹
        </button>
        <label className="text-center">
          <span className="block text-sm font-semibold">
            {dayMonth(monday)} – {dayMonth(addDays(monday, 6))}
          </span>
          <span className="text-xs text-ink-muted">Week {weekNo}</span>
          <input
            type="date"
            aria-label="Jump to week"
            min="2020-01-01"
            max={toIsoDate(now)}
            value={toIsoDate(monday)}
            onChange={(e) => e.target.value && setMonday(weekStart(parseDate(e.target.value)))}
            className="sr-only"
          />
        </label>
        <button
          type="button"
          onClick={() => setMonday(addDays(monday, 7))}
          disabled={!canNext}
          aria-label="Next week"
          className="rounded-lg px-3 py-2 hover:bg-recessed disabled:opacity-30"
        >
          ›
        </button>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <Card className="p-4">
          <Eyebrow>Income</Eyebrow>
          <Money value={s.income} tone="income" className="mt-1 block font-semibold" />
        </Card>
        <Card className="p-4">
          <Eyebrow>Expense</Eyebrow>
          <Money value={s.expense} tone="expense" className="mt-1 block font-semibold" />
        </Card>
        <Card className="p-4">
          <Eyebrow>Net</Eyebrow>
          <Money value={s.income - s.expense} className="mt-1 block font-semibold" />
        </Card>
      </div>

      <Card>
        <div className="mb-3 flex items-baseline justify-between">
          <h2 className="text-sm font-semibold">By category</h2>
          <Eyebrow>Share of expenses</Eyebrow>
        </div>
        {cats.length === 0 ? (
          <p className="text-sm text-ink-muted">No expenses in this week.</p>
        ) : (
          <>
            <div className="flex h-2.5 gap-0.5 overflow-hidden rounded-full bg-track">
              {cats.map((c, i) => (
                <div key={c.name} style={{ width: `${(c.value / catTotal) * 100}%`, background: CHART[i % 12] }} />
              ))}
            </div>
            <ul className="mt-3 space-y-2 text-sm">
              {cats.map((c, i) => (
                <li key={c.name} className="flex items-center gap-2">
                  <span className="h-2.5 w-2.5 rounded-full" style={{ background: CHART[i % 12] }} />
                  <span className="flex-1 truncate">{c.name}</span>
                  <span className="text-xs text-ink-muted">{Math.round((c.value / catTotal) * 100)}%</span>
                  <Money value={c.value} className="w-28 text-right font-medium" />
                </li>
              ))}
            </ul>
          </>
        )}
      </Card>

      <Card>
        <h2 className="mb-3 text-sm font-semibold">By account</h2>
        {accts.length === 0 ? (
          <p className="text-sm text-ink-muted">Nothing moved through your accounts this week.</p>
        ) : (
          <ul className="divide-y divide-rule">
            {accts.map((a) => {
              const n = names.get(a.accountId) ?? 'Unknown account';
              return (
                <li key={a.accountId} className="flex items-center gap-3 py-2.5 text-sm">
                  <Glyph name={n} hue={hueFor(n)} size={28} />
                  <span className="flex-1 truncate font-medium">{n}</span>
                  <span className="rounded-full bg-income-surface px-2 py-0.5 text-xs text-income">In {formatMoney(a.inflow)}</span>
                  <span className="rounded-full bg-expense-surface px-2 py-0.5 text-xs text-expense">Out {formatMoney(a.outflow)}</span>
                  <Money value={a.net} className="w-28 text-right font-semibold" />
                </li>
              );
            })}
          </ul>
        )}
      </Card>
      {txns.length === 0 && <Empty title="Nothing to report yet">Reports fill in as you add transactions.</Empty>}
    </div>
  );
}

/** ISO-8601 week number of a Monday. */
function isoWeek(monday: DateOnly): number {
  const thursday = addDays(monday, 3);
  const jan1 = Date.UTC(thursday.getUTCFullYear(), 0, 1);
  return Math.floor((thursday.getTime() - jan1) / 86_400_000 / 7) + 1;
}
