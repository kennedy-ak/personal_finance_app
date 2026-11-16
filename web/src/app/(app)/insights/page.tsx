'use client';

import Link from 'next/link';
import { useState } from 'react';
import { CoachChat } from '@/components/coach-chat';
import { DailyTip } from '@/components/daily-tip';
import { Icon } from '@/components/icons';
import { AlertList } from '@/components/money-widgets';
import { Card, ErrorNote, Eyebrow, Loading, Money, SectionTitle, Tabs } from '@/components/ui';
import { useMoney } from '@/lib/data/hooks';
import { type Account } from '@/lib/domain/account';
import { type Obligation } from '@/lib/domain/obligation';
import { type MoneySnapshot } from '@/lib/finance/money-engine';
import { formatMoney } from '@/lib/format';

type Tab = 'overview' | 'ask';

/** Port of insights/presentation/insights_screen.dart. */
export default function InsightsPage() {
  const [tab, setTab] = useState<Tab>('overview');
  // Ask AI is full-screen in the app, with its own way back.
  if (tab === 'ask') return <CoachChat onBack={() => setTab('overview')} />;

  return (
    <>
      <h1 className="mb-4 text-2xl font-semibold tracking-tight">Insights</h1>
      <Tabs<Tab>
        label="Insights"
        value={tab}
        onChange={setTab}
        options={[
          { value: 'overview', label: 'Overview' },
          { value: 'ask', label: 'Ask AI' },
        ]}
      />
      <Overview />
    </>
  );
}

function Overview() {
  const money = useMoney();
  if (!money.ready) return money.error ? <ErrorNote error={money.error} /> : <Loading />;
  const { snapshot: s, alerts, accounts, obligations, goals, txns } = money;
  const live = accounts.filter((a) => !a.isArchived);
  const gaps = gapsFor(s, live, obligations, txns.some((t) => t.isSpending));
  const activeGoals = goals.filter((g) => g.isActive);

  return (
    <div className="space-y-6">
      <DailyTip />
      <AlertList alerts={alerts} heading="Needs your attention" />

      {gaps.length > 0 && (
        <section>
          <SectionTitle>Make this sharper</SectionTitle>
          <ul className="divide-y divide-rule rounded-2xl border border-hairline bg-card">
            {gaps.map((g) => (
              <li key={g.title}>
                <Link href={g.route} className="flex items-center gap-3 px-4 py-3 hover:bg-recessed">
                  <span className="flex-1">
                    <span className="block text-sm font-medium">{g.title}</span>
                    <span className="mt-0.5 block text-xs text-ink-muted">{g.body}</span>
                  </span>
                  <Icon name="arrowRight" width={16} height={16} className="text-brand-ink" />
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <Numbers s={s} />

      {activeGoals.length > 0 && (
        <section>
          <SectionTitle
            action={
              <Link href="/plan" className="text-xs font-medium text-brand-ink hover:underline">
                Edit
              </Link>
            }
          >
            Goals
          </SectionTitle>
          <Link href="/plan" className="block space-y-4 rounded-2xl border border-hairline bg-card p-5 hover:border-outline">
            {activeGoals.map((g) => (
              <div key={g.id}>
                <div className="flex justify-between text-sm">
                  <span className="font-medium">{g.name}</span>
                  <span className="tabular text-ink-muted">
                    {formatMoney(g.savedAmount)} / {formatMoney(g.targetAmount)}
                  </span>
                </div>
                <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-track">
                  <div className="h-full rounded-full bg-protected" style={{ width: `${g.progress * 100}%` }} />
                </div>
              </div>
            ))}
          </Link>
        </section>
      )}
    </div>
  );
}

function gapsFor(s: MoneySnapshot, accounts: Account[], obligations: Obligation[], hasSpending: boolean) {
  if (accounts.length === 0) {
    return [{ title: 'Add an account', body: 'Nothing can be worked out until the app knows where your money sits.', route: '/accounts' }];
  }
  const gaps: { title: string; body: string; route: string }[] = [];
  if (!hasSpending) {
    gaps.push({
      title: 'Log some spending',
      body: 'Without transactions there is no spending rate, so the app cannot tell you how long your money lasts.',
      route: '/add',
    });
  }
  if (s.daysUntilIncome === null) {
    gaps.push({
      title: 'Record when you get paid',
      body: 'Safe-to-spend is falling back to a flat 30 days. With a real income date it becomes the amount that has to last until then.',
      route: '/plan',
    });
  }
  if (!obligations.some((o) => o.isActive && o.isOutflow)) {
    gaps.push({
      title: 'Add your bills',
      body: 'Rent and subscriptions are counted as spendable right now, so your safe-to-spend is higher than it really is.',
      route: '/plan',
    });
  }
  const spendable = accounts.filter((a) => a.isSpendable);
  if (spendable.length > 1 && spendable.every((a) => a.minBalance === 0)) {
    gaps.push({
      title: `Set a floor on ${spendable[0].name}`,
      body: 'Nothing is protected, so a payment can be suggested from any account right down to zero.',
      route: '/accounts',
    });
  }
  return gaps;
}

function Numbers({ s }: { s: MoneySnapshot }) {
  if (s.spend30d <= 0 && s.income30d <= 0) return null;
  const tiles: { label: string; value: React.ReactNode }[] = [];
  if (s.income30d > 0) tiles.push({ label: 'Kept of income', value: `${Math.round(((s.income30d - s.spend30d) / s.income30d) * 100)}%` });
  if (s.dailyBurn > 0) tiles.push({ label: 'Spending a day', value: <Money value={s.dailyBurn} /> });
  if (s.runwayDays !== null) tiles.push({ label: 'Cash lasts', value: `${Math.floor(s.runwayDays)} days` });
  if (s.committed > 0) tiles.push({ label: 'Committed', value: <Money value={s.committed} /> });
  if (s.categories.length > 0 && s.spend30d > 0) tiles.push({ label: 'Biggest category', value: s.categories[0].category });
  if (tiles.length === 0) return null;

  return (
    <section>
      <SectionTitle>Your numbers</SectionTitle>
      <div className="grid grid-cols-2 gap-2">
        {tiles.map((t, i) => (
          <Card key={t.label} className={i === tiles.length - 1 && tiles.length % 2 === 1 ? 'col-span-2 p-4' : 'p-4'}>
            <Eyebrow>{t.label}</Eyebrow>
            <div className="mt-1 text-lg font-semibold">{t.value}</div>
          </Card>
        ))}
      </div>
    </section>
  );
}
