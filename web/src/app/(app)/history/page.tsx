'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { Icon } from '@/components/icons';
import { TxnRow } from '@/components/txn-row';
import {
  Button,
  Confirm,
  Dialog,
  Empty,
  ErrorNote,
  Eyebrow,
  Glyph,
  Input,
  Loading,
  cx,
} from '@/components/ui';
import { downloadText, transactionsToCsv } from '@/lib/csv';
import { MONEY_KEYS, useAccounts, useTransactions, useWrite } from '@/lib/data/hooks';
import { transactionsRepo } from '@/lib/data/repositories';
import { toIsoDate } from '@/lib/dates';
import { type Txn, type TxnType } from '@/lib/domain/transaction';
import { dateLong, formatMoney, timeOfDay } from '@/lib/format';
import { dayHeader, hueFor, plural, titleForTxn } from '@/lib/present';

interface Filter {
  type: TxnType | null;
  accountId: string | null;
  category: string | null;
}
const NO_FILTER: Filter = { type: null, accountId: null, category: null };
const activeCount = (f: Filter) => [f.type, f.accountId, f.category].filter(Boolean).length;

/** Port of transactions/presentation/history_screen.dart. */
export default function HistoryPage() {
  const txnsQ = useTransactions();
  const accountsQ = useAccounts();
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<Filter>(NO_FILTER);
  const [filterOpen, setFilterOpen] = useState(false);
  const [detail, setDetail] = useState<Txn | null>(null);

  const names = useMemo(() => new Map((accountsQ.data ?? []).map((a) => [a.id, a.name])), [accountsQ.data]);
  const accountName = (id: string) => names.get(id) ?? 'Unknown account';
  const all = useMemo(() => txnsQ.data ?? [], [txnsQ.data]);

  const apply = (f: Filter, q: string) => {
    const needle = q.trim().toLowerCase();
    return all.filter((t) => {
      if (f.type && t.type !== f.type) return false;
      if (f.accountId && t.accountId !== f.accountId && t.toAccountId !== f.accountId) return false;
      if (f.category && t.category !== f.category) return false;
      if (needle) {
        const hay = [t.category, t.description ?? '', names.get(t.accountId) ?? '', t.amount.toFixed(2)]
          .join(' ')
          .toLowerCase();
        if (!hay.includes(needle)) return false;
      }
      return true;
    });
  };
  const filtered = apply(filter, query);

  if (txnsQ.isLoading || accountsQ.isLoading) return <Loading />;
  if (txnsQ.error || accountsQ.error) return <ErrorNote error={txnsQ.error ?? accountsQ.error} />;

  const groups = groupByDay(filtered);
  const nFilters = activeCount(filter);

  return (
    <>
      <header className="mb-5 flex items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">History</h1>
          <Eyebrow className="mt-1">{plural(filtered.length, 'row')}</Eyebrow>
        </div>
        {filtered.length > 0 && (
          <Button
            variant="secondary"
            onClick={() =>
              downloadText(`transactions-${toIsoDate(new Date())}.csv`, transactionsToCsv(filtered, accountName))
            }
          >
            <Icon name="download" width={16} height={16} /> Export CSV
          </Button>
        )}
      </header>

      {all.length > 0 && (
        <div className="mb-3 flex gap-2">
          <Input
            type="search"
            placeholder="Search description or amount"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label="Search"
          />
          <Button variant="secondary" onClick={() => setFilterOpen(true)} aria-label="Filters">
            Filters
            {nFilters > 0 && (
              <span className="rounded-full bg-brand px-1.5 text-[11px] text-on-brand">{nFilters}</span>
            )}
          </Button>
        </div>
      )}

      {nFilters > 0 && (
        <div className="mb-4 flex flex-wrap gap-2">
          {filter.type && <Chip label={filter.type} onRemove={() => setFilter({ ...filter, type: null })} />}
          {filter.accountId && (
            <Chip label={accountName(filter.accountId)} onRemove={() => setFilter({ ...filter, accountId: null })} />
          )}
          {filter.category && (
            <Chip label={filter.category} onRemove={() => setFilter({ ...filter, category: null })} />
          )}
          <button type="button" onClick={() => setFilter(NO_FILTER)} className="text-xs font-medium text-brand-ink">
            Clear
          </button>
        </div>
      )}

      {all.length === 0 ? (
        <Empty title="No transactions yet">
          <p>Log one payment and the dashboard can start telling you what is safe to spend.</p>
          <Link href="/add" className="mt-3 inline-block font-medium text-brand-ink hover:underline">
            Add transaction
          </Link>
        </Empty>
      ) : filtered.length === 0 ? (
        <Empty title={query.trim() ? `Nothing matches “${query.trim()}”` : 'Nothing matches those filters'}>
          <p>
            {query.trim()
              ? 'Try a shorter search, or a figure without the currency.'
              : `${plural(nFilters, 'filter')} ${nFilters === 1 ? 'is' : 'are'} still on. Clearing ${nFilters === 1 ? 'it' : 'them'} searches all ${all.length} rows.`}
          </p>
          <button
            type="button"
            onClick={() => {
              setQuery('');
              setFilter(NO_FILTER);
            }}
            className="mt-3 font-medium text-brand-ink hover:underline"
          >
            {query.trim() ? 'Clear search' : 'Clear filters'}
          </button>
        </Empty>
      ) : (
        <div className="space-y-5">
          {groups.map(({ key, rows, net }) => (
            <section key={key}>
              <div className="mb-1.5 flex items-baseline justify-between px-2">
                <h2 className="font-mono text-[11px] uppercase tracking-wider text-ink-faint">
                  {dayHeader(rows[0].date)}
                </h2>
                <span
                  className={cx(
                    'tabular text-xs font-medium',
                    net < 0 ? 'text-expense' : net > 0 ? 'text-income' : 'text-ink-faint',
                  )}
                >
                  {net > 0 ? '+' : ''}
                  {formatMoney(net)}
                </span>
              </div>
              <ul className="rounded-2xl border border-hairline bg-card p-1">
                {rows.map((t) => (
                  <TxnRow
                    key={t.id}
                    t={t}
                    accountName={accountName}
                    subtitle="account-category-time"
                    onClick={() => setDetail(t)}
                  />
                ))}
              </ul>
            </section>
          ))}
        </div>
      )}

      <FilterDialog
        key={filterOpen ? 'open' : 'closed'}
        open={filterOpen}
        initial={filter}
        accounts={accountsQ.data ?? []}
        categories={[...new Set(all.map((t) => t.category))].sort((a, b) => a.localeCompare(b))}
        countFor={(f) => apply(f, query).length}
        onApply={(f) => {
          setFilter(f);
          setFilterOpen(false);
        }}
        onClose={() => setFilterOpen(false)}
      />

      <DetailDialog t={detail} accountName={accountName} onClose={() => setDetail(null)} />
    </>
  );
}

function groupByDay(txns: Txn[]) {
  const map = new Map<string, Txn[]>();
  for (const t of txns) {
    const k = toIsoDate(t.date);
    const list = map.get(k);
    if (list) list.push(t);
    else map.set(k, [t]);
  }
  return [...map.entries()].map(([key, rows]) => ({
    key,
    rows,
    // Income minus spending; transfers count zero.
    net: rows.reduce((s, t) => s + (t.isIncome ? t.amount : t.isSpending ? -t.amount : 0), 0),
  }));
}

function Chip({ label, onRemove }: { label: string; onRemove: () => void }) {
  return (
    <button
      type="button"
      onClick={onRemove}
      aria-label={`Remove filter ${label}`}
      className="flex items-center gap-1 rounded-full border border-hairline bg-card px-3 py-1 text-xs"
    >
      {label} <span aria-hidden>✕</span>
    </button>
  );
}

function ChipGroup<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: T | null;
  options: { value: T; label: string }[];
  onChange: (v: T | null) => void;
}) {
  return (
    <fieldset>
      <legend className="mb-2 text-xs font-medium text-ink-muted">{label}</legend>
      <div className="flex flex-wrap gap-2">
        {options.map((o) => (
          <button
            key={o.value}
            type="button"
            aria-pressed={value === o.value}
            onClick={() => onChange(value === o.value ? null : o.value)}
            className={cx(
              'rounded-full border px-3 py-1 text-sm',
              value === o.value ? 'border-brand-ink bg-info-surface text-brand-ink' : 'border-hairline text-ink-body',
            )}
          >
            {o.label}
          </button>
        ))}
      </div>
    </fieldset>
  );
}

function FilterDialog({
  open,
  initial,
  accounts,
  categories,
  countFor,
  onApply,
  onClose,
}: {
  open: boolean;
  initial: Filter;
  accounts: { id: string; name: string }[];
  categories: string[];
  countFor: (f: Filter) => number;
  onApply: (f: Filter) => void;
  onClose: () => void;
}) {
  // A draft: nothing changes until "Show N transactions".
  const [draft, setDraft] = useState<Filter>(initial);
  const n = countFor(draft);
  return (
    <Dialog open={open} onClose={onClose} title="Filter">
      <div className="space-y-5">
        <ChipGroup<TxnType>
          label="Type"
          value={draft.type}
          onChange={(type) => setDraft({ ...draft, type })}
          options={(['Expense', 'Income', 'Transfer'] as const).map((t) => ({ value: t, label: t }))}
        />
        <ChipGroup
          label="Account"
          value={draft.accountId}
          onChange={(accountId) => setDraft({ ...draft, accountId })}
          options={accounts.map((a) => ({ value: a.id, label: a.name }))}
        />
        <ChipGroup
          label="Category"
          value={draft.category}
          onChange={(category) => setDraft({ ...draft, category })}
          options={categories.map((c) => ({ value: c, label: c }))}
        />
        <div className="flex items-center justify-between gap-2 pt-2">
          {activeCount(draft) > 0 ? (
            <Button variant="ghost" onClick={() => setDraft(NO_FILTER)}>
              Reset
            </Button>
          ) : (
            <span />
          )}
          <Button onClick={() => onApply(draft)}>
            {n === 0 ? 'No transactions match' : `Show ${plural(n, 'transaction')}`}
          </Button>
        </div>
        {n === 0 && <p className="text-right text-xs text-ink-faint">Applying this shows the no-results screen.</p>}
      </div>
    </Dialog>
  );
}

function DetailDialog({
  t,
  accountName,
  onClose,
}: {
  t: Txn | null;
  accountName: (id: string) => string;
  onClose: () => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const remove = useWrite(async (id: string) => transactionsRepo.remove(id), MONEY_KEYS);
  if (!t) return <Dialog open={false} onClose={onClose} title="">{null}</Dialog>;

  const title = t.description || titleForTxn(t, accountName);
  const rows: [string, string][] = [
    ['Date', dateLong(t.date)],
    ['Time', timeOfDay(t.createdAt)],
    ['Account', accountName(t.accountId)],
    ...(t.type === 'Transfer' && t.toAccountId ? ([['To', accountName(t.toAccountId)]] as [string, string][]) : []),
    ...(t.type !== 'Transfer' ? ([['Category', t.category]] as [string, string][]) : []),
    ...(t.description ? ([['Note', t.description]] as [string, string][]) : []),
  ];

  return (
    <>
      <Dialog open={!confirming} onClose={onClose} title={title}>
        <div className="flex items-center gap-3">
          <Glyph name={t.category} hue={hueFor(t.category)} neutral={t.type === 'Transfer'} size={44} />
          <div>
            <Eyebrow>{t.type}</Eyebrow>
            <div
              className={cx(
                'tabular text-2xl font-semibold',
                t.type === 'Income' ? 'text-income' : t.type === 'Expense' ? 'text-expense' : 'text-ink-muted',
              )}
            >
              {t.type === 'Income' ? '+' : t.type === 'Expense' ? '-' : ''}
              {formatMoney(t.amount)}
            </div>
          </div>
        </div>
        <dl className="mt-5 divide-y divide-rule text-sm">
          {rows.map(([k, v]) => (
            <div key={k} className="flex justify-between gap-4 py-2">
              <dt className="text-ink-muted">{k}</dt>
              <dd className="text-right">{v}</dd>
            </div>
          ))}
        </dl>
        <div className="mt-5 flex justify-between gap-2">
          <Button variant="danger" onClick={() => setConfirming(true)}>
            Delete transaction
          </Button>
          <Button variant="secondary" onClick={onClose}>
            Close
          </Button>
        </div>
      </Dialog>
      <Confirm
        open={confirming}
        title="Delete this transaction?"
        body={`${title} · ${formatMoney(t.amount)} will be removed and your balances will settle back.`}
        confirmLabel="Delete"
        danger
        busy={remove.isPending}
        error={remove.error}
        onClose={() => setConfirming(false)}
        onConfirm={() =>
          remove.mutate(t.id, {
            onSuccess: () => {
              setConfirming(false);
              onClose();
            },
          })
        }
      />
    </>
  );
}
