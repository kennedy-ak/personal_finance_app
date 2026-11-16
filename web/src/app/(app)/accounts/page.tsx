'use client';

import Link from 'next/link';
import { useState } from 'react';
import { Icon } from '@/components/icons';
import {
  Button,
  Card,
  Confirm,
  Dialog,
  ErrorNote,
  Eyebrow,
  Field,
  Input,
  Loading,
  Money,
  Segmented,
  Select,
  Textarea,
  cx,
  parseAmount,
} from '@/components/ui';
import { keys, MONEY_KEYS, useMoney, useWrite } from '@/lib/data/hooks';
import { accountsRepo } from '@/lib/data/repositories';
import {
  ACCOUNT_KINDS,
  LIQUIDITIES,
  kindLabel,
  type Account,
  type AccountKind,
  type Liquidity,
} from '@/lib/domain/account';
import { formatMoney } from '@/lib/format';
import { plural } from '@/lib/present';

const CHART = ['#0E7C66', '#F59E0B', '#8B5CF6', '#EF4444', '#3B82F6', '#EC4899', '#14B8A6', '#EAB308', '#6366F1', '#10B981', '#F97316', '#06B6D4'];

const ACCESS: Record<Liquidity, (k: AccountKind) => string> = {
  liquid: (k) => (k === 'bank' ? 'liquid in 1 day' : 'instant'),
  reserved: () => 'reserved',
  locked: () => 'locked',
};

const LIQ_HELP: Record<Liquidity, string> = {
  liquid: 'Counts towards safe-to-spend.',
  reserved: 'Meant for something. Held out of safe-to-spend, offered only under protest.',
  locked: 'Fixed deposit or investment. Never offered for spending.',
};

type Editing = { account: Account | null; kind: AccountKind } | null;

/** Port of accounts/presentation/accounts_screen.dart. */
export default function AccountsPage() {
  const money = useMoney();
  const [editing, setEditing] = useState<Editing>(null);

  if (!money.ready) return money.error ? <ErrorNote error={money.error} /> : <Loading />;

  const { accounts, obligations, goals } = money;
  const active = accounts.filter((a) => !a.isArchived);
  const archived = accounts.filter((a) => a.isArchived);
  const open = (account: Account | null, kind: AccountKind = account?.kind ?? 'bank') =>
    setEditing({ account, kind });

  const editor = (
    <AccountDialog
      key={editing ? (editing.account?.id ?? `new-${editing.kind}`) : 'closed'}
      editing={editing}
      nextSortOrder={accounts.length}
      onClose={() => setEditing(null)}
    />
  );

  if (active.length === 0) {
    return (
      <div className="mx-auto max-w-xl">
        <h1 className="mb-6 text-2xl font-semibold tracking-tight">Accounts</h1>
        <div className="rounded-2xl border-2 border-dashed border-outline p-6">
          <h2 className="text-lg font-semibold">Add where your money actually is</h2>
          <p className="mt-2 text-sm text-ink-muted">
            Nothing can be called safe to spend until the app knows your balances. Most people start with one bank
            and one Momo wallet.
          </p>
        </div>
        <div className="mt-4 grid gap-3">
          {(
            [
              ['bank', 'Bank account', 'Fidelity, GCB, Absa'],
              ['momo', 'Mobile Money', 'MTN, Vodafone Cash, AirtelTigo'],
              ['cash', 'Cash', 'What is in your pocket'],
            ] as const
          ).map(([kind, title, sub]) => (
            <button
              key={kind}
              type="button"
              onClick={() => open(null, kind)}
              className="flex items-center justify-between rounded-2xl border border-hairline bg-card p-4 text-left hover:border-outline"
            >
              <span>
                <span className="block font-medium">{title}</span>
                <span className="text-sm text-ink-muted">{sub}</span>
              </span>
              <Icon name="plus" />
            </button>
          ))}
        </div>
        <Button className="mt-6 h-12 w-full" onClick={() => open(null, 'bank')}>
          Add first account
        </Button>
        {editor}
      </div>
    );
  }

  const total = active.reduce((s, a) => s + a.balance, 0);
  const positive = active.filter((a) => a.balance > 0).sort((a, b) => b.balance - a.balance);
  const posTotal = positive.reduce((s, a) => s + a.balance, 0);
  const bills = obligations.filter((o) => o.isActive && o.isOutflow).length;
  const activeGoals = goals.filter((g) => g.isActive).length;

  return (
    <>
      <header className="mb-6 flex items-end justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">Accounts</h1>
        <Button variant="secondary" onClick={() => open(null)}>
          <Icon name="plus" width={16} height={16} /> Add
        </Button>
      </header>

      <Card className="mb-6">
        <div className="flex items-baseline gap-2">
          <Money value={total} className="text-3xl font-semibold" />
          <span className="text-sm text-ink-muted">across {plural(active.length, 'account')}</span>
        </div>
        {posTotal > 0 && (
          <>
            <div className="mt-4 flex h-2.5 gap-0.5 overflow-hidden rounded-full bg-track">
              {positive.map((a, i) => (
                <div key={a.id} style={{ width: `${(a.balance / posTotal) * 100}%`, background: CHART[i % 12] }} />
              ))}
            </div>
            <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-ink-muted">
              {positive.map((a, i) => (
                <li key={a.id} className="flex items-center gap-1.5">
                  <span className="h-2 w-2 rounded-full" style={{ background: CHART[i % 12] }} />
                  {a.name} {Math.round((a.balance / posTotal) * 100)}%
                </li>
              ))}
            </ul>
          </>
        )}
      </Card>

      <ul className="grid gap-3 sm:grid-cols-2">
        {active.map((a) => (
          <AccountCard key={a.id} a={a} onOpen={() => open(a)} />
        ))}
      </ul>

      {archived.length > 0 && (
        <section className="mt-8">
          <h2 className="mb-3 text-sm font-semibold text-ink-muted">Archived</h2>
          <ul className="grid gap-3 opacity-70 sm:grid-cols-2">
            {archived.map((a) => (
              <AccountCard key={a.id} a={a} onOpen={() => open(a)} />
            ))}
          </ul>
        </section>
      )}

      <Link
        href="/plan"
        className="mt-6 flex items-center justify-between rounded-2xl border border-hairline bg-card p-4 hover:border-outline"
      >
        <span>
          <span className="block font-medium">Commitments & goals</span>
          <span className="text-sm text-ink-muted">
            {bills + activeGoals > 0
              ? `${plural(bills, 'bill')} · ${plural(activeGoals, 'goal')}`
              : 'Bills, expected income and money you protect'}
          </span>
        </span>
        <Icon name="arrowRight" />
      </Link>

      {editor}
    </>
  );
}

function AccountCard({ a, onOpen }: { a: Account; onOpen: () => void }) {
  const held = a.minBalance > 0 && a.balance > 0 ? Math.min(1, a.minBalance / a.balance) : a.minBalance > 0 ? 1 : 0;
  return (
    <li>
      <button
        type="button"
        onClick={onOpen}
        aria-label={`${a.name}, ${formatMoney(a.balance)}. Edit.`}
        className="block w-full rounded-2xl border border-hairline bg-card p-5 text-left hover:border-outline"
      >
        <Eyebrow>
          {kindLabel(a.kind)} · {ACCESS[a.liquidity](a.kind)}
        </Eyebrow>
        <h2 className="mt-1 truncate font-semibold">{a.name}</h2>
        <Money value={a.balance} tone={a.isBelowFloor ? 'expense' : undefined} className="mt-3 block text-2xl font-semibold" />
        {a.minBalance > 0 ? (
          <>
            <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-track">
              <div className={cx('h-full', a.isBelowFloor ? 'bg-expense' : 'bg-protected')} style={{ width: `${held * 100}%` }} />
            </div>
            <p className={cx('mt-1.5 text-xs', a.isBelowFloor ? 'text-expense' : 'text-ink-muted')}>
              {a.isBelowFloor
                ? `Below its floor of ${formatMoney(a.minBalance)}`
                : `Floor ${formatMoney(a.minBalance)} · ${Math.round(held * 100)}% held back`}
            </p>
          </>
        ) : (
          <p className="mt-3 text-xs text-ink-muted">
            {a.liquidity === 'liquid' ? 'No floor set · all of it counts as spendable' : 'Held out of safe-to-spend'}
          </p>
        )}
        {a.purpose && <p className="mt-2 text-sm text-ink-body">{a.purpose}</p>}
      </button>
    </li>
  );
}

function AccountDialog({
  editing,
  nextSortOrder,
  onClose,
}: {
  editing: Editing;
  nextSortOrder: number;
  onClose: () => void;
}) {
  const existing = editing?.account ?? null;
  const [name, setName] = useState(existing?.name ?? '');
  const [kind, setKind] = useState<AccountKind>(existing?.kind ?? editing?.kind ?? 'bank');
  const [liquidity, setLiquidity] = useState<Liquidity>(existing?.liquidity ?? 'liquid');
  const [balance, setBalance] = useState(existing ? existing.balance.toFixed(2) : '0.00');
  const [minBalance, setMinBalance] = useState(existing ? existing.minBalance.toFixed(2) : '0.00');
  const [purpose, setPurpose] = useState(existing?.purpose ?? '');
  const [error, setError] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const save = useWrite(async () => {
    const bal = parseAmount(balance);
    const floor = parseAmount(minBalance);
    if (!name.trim()) throw new Error('Give it a name');
    if (bal === null) throw new Error('Enter a balance');
    if (floor === null || floor < 0) throw new Error('Floor must be zero or more');
    if (existing) {
      await accountsRepo.update(existing.id, { name: name.trim(), kind, liquidity, minBalance: floor, purpose: purpose.trim() });
      await accountsRepo.reconcileBalance(existing, bal);
    } else {
      await accountsRepo.create({
        name: name.trim(),
        openingBalance: bal,
        kind,
        liquidity,
        minBalance: floor,
        purpose: purpose.trim() || null,
        sortOrder: nextSortOrder,
      });
    }
  }, [keys.accounts]);

  const archive = useWrite(async () => {
    if (existing) await accountsRepo.update(existing.id, { isArchived: !existing.isArchived });
  }, [keys.accounts]);
  const remove = useWrite(async () => {
    if (existing) await accountsRepo.remove(existing.id);
  }, MONEY_KEYS);

  const run = (m: typeof save) => m.mutate(undefined, { onSuccess: onClose, onError: (e) => setError(e.message) });

  return (
    <>
      <Dialog open={editing !== null && !confirmDelete} onClose={onClose} title={existing ? 'Edit account' : 'New account'}>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            run(save);
          }}
          className="space-y-4"
        >
          <Field label="Name">
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Fidelity Bank" autoFocus />
          </Field>
          <Field label="Kind">
            <Select value={kind} onChange={(e) => setKind(e.target.value as AccountKind)}>
              {ACCOUNT_KINDS.map((k) => (
                <option key={k.value} value={k.value}>
                  {k.label}
                </option>
              ))}
            </Select>
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label={existing ? 'Balance' : 'Starting balance'}>
              <Input inputMode="decimal" value={balance} onChange={(e) => setBalance(e.target.value)} />
            </Field>
            <Field label="Floor">
              <Input inputMode="decimal" value={minBalance} onChange={(e) => setMinBalance(e.target.value)} />
            </Field>
          </div>
          <p className="text-xs text-ink-faint">
            {existing
              ? 'Correcting the balance adjusts the opening figure, not your history.'
              : 'The floor is what the app will never suggest dipping below.'}
          </p>
          <div>
            <span className="mb-1.5 block text-xs font-medium text-ink-muted">Availability</span>
            <Segmented<Liquidity>
              label="Availability"
              value={liquidity}
              onChange={setLiquidity}
              options={LIQUIDITIES.map((l) => ({ value: l.value, label: l.label }))}
            />
            <p className="mt-1.5 text-xs text-ink-faint">{LIQ_HELP[liquidity]}</p>
          </div>
          <Field label="What is it for? (optional)">
            <Textarea
              rows={2}
              value={purpose}
              onChange={(e) => setPurpose(e.target.value)}
              placeholder="Rent and utilities leave from here"
            />
          </Field>

          <ErrorNote error={error} />

          <div className="flex flex-wrap items-center justify-between gap-2 pt-2">
            {existing ? (
              <div className="flex gap-1">
                <Button type="button" variant="ghost" busy={archive.isPending} onClick={() => run(archive)}>
                  <Icon name="archive" width={16} height={16} />
                  {existing.isArchived ? 'Unarchive' : 'Archive'}
                </Button>
                <Button type="button" variant="ghost" onClick={() => setConfirmDelete(true)}>
                  <Icon name="trash" width={16} height={16} /> Delete
                </Button>
              </div>
            ) : (
              <span />
            )}
            <Button type="submit" busy={save.isPending}>
              {existing ? 'Save' : 'Add account'}
            </Button>
          </div>
        </form>
      </Dialog>
      <Confirm
        open={confirmDelete}
        title={`Delete "${existing?.name ?? ''}"?`}
        body="This also deletes every transaction on it, on every device, and cannot be undone. Archiving keeps the history instead."
        confirmLabel="Delete permanently"
        cancelLabel="Keep it"
        danger
        busy={remove.isPending}
        error={remove.error}
        onClose={() => setConfirmDelete(false)}
        onConfirm={() => run(remove)}
      />
    </>
  );
}
