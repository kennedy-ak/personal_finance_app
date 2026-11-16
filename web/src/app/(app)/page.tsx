'use client';

import { useQueryClient } from '@tanstack/react-query';
import Link from 'next/link';
import { useState } from 'react';
import { Icon } from '@/components/icons';
import {
  AlertList,
  MoneyPlacement,
  PayButton,
  SafeToSpendHero,
  SpendingMovement,
  heroState,
} from '@/components/money-widgets';
import { TxnRow } from '@/components/txn-row';
import { Button, Card, Empty, ErrorNote, Eyebrow, Loading, SectionTitle } from '@/components/ui';
import { keys, useMe, useMoney } from '@/lib/data/hooks';
import { displayName, greeting } from '@/lib/present';

/** Port of dashboard/presentation/dashboard_screen.dart. */
export default function DashboardPage() {
  const money = useMoney();
  const me = useMe();
  const qc = useQueryClient();
  const [refreshing, setRefreshing] = useState(false);

  async function refresh() {
    setRefreshing(true);
    await Promise.all(
      [keys.accounts, keys.transactions, keys.obligations, keys.goals].map((k) =>
        qc.invalidateQueries({ queryKey: k }),
      ),
    );
    setRefreshing(false);
  }

  if (!money.ready) {
    return money.error ? (
      <div className="space-y-3">
        <p className="font-medium">Could not work out your position</p>
        <ErrorNote error={money.error} />
        <Button variant="secondary" onClick={refresh}>
          Retry
        </Button>
      </div>
    ) : (
      <Loading />
    );
  }

  const { snapshot: s, alerts, txns, accounts } = money;
  const names = new Map(accounts.map((a) => [a.id, a.name]));
  const name = displayName(me.data?.user_metadata?.full_name as string | undefined, me.data?.email);
  const shortfall = heroState(s) === 'shortfall';

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-3">
        <div>
          <Eyebrow>{greeting(new Date())}</Eyebrow>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">{name ? `Hello, ${name}` : 'Hello'}</h1>
        </div>
        <div className="flex gap-1">
          <button
            type="button"
            onClick={refresh}
            aria-label="Refresh"
            className="rounded-lg p-2 text-ink-muted hover:bg-recessed hover:text-ink"
          >
            <Icon name="history" className={refreshing ? 'animate-spin' : undefined} />
          </button>
          <Link href="/settings" aria-label="Settings" className="rounded-lg p-2 text-ink-muted hover:bg-recessed hover:text-ink">
            <Icon name="settings" />
          </Link>
        </div>
      </div>

      <SafeToSpendHero s={s} />

      {!shortfall && <PayButton />}

      <AlertList alerts={alerts} heading={shortfall ? 'What closes the gap' : 'Needs a decision'} />

      {shortfall && (
        <div className="grid gap-2 sm:grid-cols-2">
          <Link
            href="/plan"
            className="flex h-12 items-center justify-center rounded-2xl bg-brand text-sm font-medium text-on-brand hover:bg-brand-pressed"
          >
            Work through the gap
          </Link>
          <PayButton secondary />
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        <MoneyPlacement s={s} />
        <SpendingMovement s={s} />
      </div>

      <Card>
        <SectionTitle
          action={
            <Link href="/history" className="text-xs font-medium text-brand-ink hover:underline">
              See all
            </Link>
          }
        >
          Recent
        </SectionTitle>
        {txns.length === 0 ? (
          <Empty title="Nothing here yet">
            <p>Add your first transaction and the dashboard starts working.</p>
            <Link href="/add" className="mt-2 inline-block font-medium text-brand-ink hover:underline">
              Add transaction
            </Link>
          </Empty>
        ) : (
          <ul className="-mx-2 divide-y divide-rule">
            {txns.slice(0, 4).map((t) => (
              <TxnRow key={t.id} t={t} accountName={(id) => names.get(id) ?? '—'} subtitle="account-date" />
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
