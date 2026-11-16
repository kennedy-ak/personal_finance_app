'use client';

import { useState } from 'react';
import { Icon } from '@/components/icons';
import {
  Badge,
  Button,
  Card,
  Confirm,
  Dialog,
  Empty,
  ErrorNote,
  Eyebrow,
  Field,
  Input,
  Loading,
  Money,
  Segmented,
  Select,
  Tabs,
  cx,
  parseAmount,
} from '@/components/ui';
import { keys, useCategoryNames, useMoney, useWrite } from '@/lib/data/hooks';
import { goalsRepo, obligationsRepo } from '@/lib/data/repositories';
import { addDays, addMonths, parseDate, toIsoDate, today, tryParseDate } from '@/lib/dates';
import { type Account } from '@/lib/domain/account';
import { type Goal } from '@/lib/domain/goal';
import {
  CADENCES,
  cadenceLabel,
  type Cadence,
  type Obligation,
  type ObligationDirection,
} from '@/lib/domain/obligation';
import { type MoneySnapshot } from '@/lib/finance/money-engine';
import { dateLong, dayMonth, formatMoney } from '@/lib/format';

type Tab = 'bills' | 'goals';

/** Port of planning/presentation/plan_screen.dart ("Commitments"). */
export default function PlanPage() {
  const money = useMoney();
  const [tab, setTab] = useState<Tab>('bills');
  const [editingOb, setEditingOb] = useState<Obligation | 'new' | null>(null);
  const [editingGoal, setEditingGoal] = useState<Goal | 'new' | null>(null);

  if (!money.ready) return money.error ? <ErrorNote error={money.error} /> : <Loading />;

  const { snapshot: s, obligations, goals, accounts } = money;
  const live = accounts.filter((a) => !a.isArchived);
  const name = (id: string | null) => live.find((a) => a.id === id)?.name;
  const now = today();

  const nextOf = (o: Obligation) => o.nextOccurrenceOnOrAfter(now) ?? o.nextDue;
  const active = obligations.filter((o) => o.isActive);
  const paused = obligations.filter((o) => !o.isActive);
  const byDue = (a: Obligation, b: Obligation) => nextOf(a).getTime() - nextOf(b).getTime();
  const ordered = [
    ...active.filter((o) => o.isOutflow).sort(byDue),
    ...active.filter((o) => !o.isOutflow).sort(byDue),
    ...paused,
  ];

  return (
    <>
      <header className="mb-4 flex items-end justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">Commitments</h1>
        <Button variant="secondary" onClick={() => (tab === 'bills' ? setEditingOb('new') : setEditingGoal('new'))}>
          <Icon name="plus" width={16} height={16} /> Add
        </Button>
      </header>

      <Tabs<Tab>
        label="Commitments"
        value={tab}
        onChange={setTab}
        options={[
          { value: 'bills', label: 'Bills & income' },
          { value: 'goals', label: 'Goals' },
        ]}
      />

      {tab === 'bills' ? (
        ordered.length === 0 ? (
          <Empty title="Nothing committed yet">
            <p>
              Add your rent, subscriptions and salary. Until the app knows what is already owed, a balance is just a
              number.
            </p>
            <Button className="mt-4" onClick={() => setEditingOb('new')}>
              Add a commitment
            </Button>
          </Empty>
        ) : (
          <div className="space-y-4">
            <Summary s={s} />
            <ul className="space-y-2">
              {ordered.map((o) => (
                <ObligationCard
                  key={o.id}
                  o={o}
                  next={nextOf(o)}
                  s={s}
                  accountName={name(o.accountId)}
                  onOpen={() => setEditingOb(o)}
                />
              ))}
            </ul>
          </div>
        )
      ) : goals.length === 0 ? (
        <Empty title="No goals yet">
          <p>
            Money you name is money you keep. A goal is held out of safe-to-spend, so it stops being spent by accident.
          </p>
          <Button className="mt-4" onClick={() => setEditingGoal('new')}>
            Add a goal
          </Button>
        </Empty>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2">
          {goals.map((g) => (
            <GoalCard key={g.id} goal={g} accountName={name(g.accountId)} onEdit={() => setEditingGoal(g)} />
          ))}
        </ul>
      )}

      <ObligationDialog
        key={editingOb === null ? 'x' : editingOb === 'new' ? 'new' : editingOb.id}
        value={editingOb}
        accounts={live}
        onClose={() => setEditingOb(null)}
      />
      <GoalDialog
        key={editingGoal === null ? 'x' : editingGoal === 'new' ? 'new' : editingGoal.id}
        value={editingGoal}
        accounts={live}
        nextPriority={goals.length}
        onClose={() => setEditingGoal(null)}
      />
    </>
  );
}

function Summary({ s }: { s: MoneySnapshot }) {
  const covered = s.committed <= s.usableCash;
  return (
    <Card>
      <Eyebrow>Leaving before {dayMonth(s.horizon)}</Eyebrow>
      <Money value={s.committed} className="mt-1 block text-2xl font-semibold" />
      <p className={cx('mt-1 text-sm', covered ? 'text-ink-muted' : 'text-expense')}>
        {covered
          ? `Your accounts cover all of it. ${formatMoney(s.usableCash - s.committed)} is left over.`
          : `That is more than the ${formatMoney(Math.max(0, s.usableCash))} you can currently reach.`}
      </p>
    </Card>
  );
}

function ObligationCard({
  o,
  next,
  s,
  accountName,
  onOpen,
}: {
  o: Obligation;
  next: Date;
  s: MoneySnapshot;
  accountName?: string;
  onOpen: () => void;
}) {
  let tone = 'border-hairline bg-card';
  let eyebrow: string;
  let detail: string;
  if (!o.isOutflow) {
    tone = 'border-income-border bg-income-surface';
    eyebrow = `Income · ${dateLong(next)}`;
    detail = `Into ${accountName ?? 'no account set'}, ${cadenceLabel(o.cadence).toLowerCase()}`;
  } else {
    const st = o.accountId ? s.standings.find((x) => x.account.id === o.accountId) : undefined;
    const available = st ? st.available : s.usableCash;
    const coveredBill = available >= o.amount;
    eyebrow = `${coveredBill ? 'Covered' : 'Not covered'} · due ${dateLong(next)}`;
    if (!coveredBill && o.isActive) {
      tone = 'border-expense-border bg-expense-surface';
      detail = `${accountName ?? 'Your accounts'} ${accountName ? 'is' : 'are'} short ${formatMoney(o.amount - Math.max(0, available))} for this.`;
    } else {
      detail = accountName
        ? `From ${accountName}, ${cadenceLabel(o.cadence).toLowerCase()}`
        : `No account set, ${cadenceLabel(o.cadence).toLowerCase()}`;
    }
  }
  return (
    <li>
      <button type="button" onClick={onOpen} className={cx('flex w-full items-center gap-3 rounded-2xl border p-4 text-left', tone)}>
        <div className="min-w-0 flex-1">
          <Eyebrow>{eyebrow}</Eyebrow>
          <div className="mt-1 flex items-center gap-2">
            <span className="truncate font-medium">{o.name}</span>
            {!o.isActive && <Badge>Paused</Badge>}
          </div>
          <p className="mt-0.5 text-sm text-ink-muted">{detail}</p>
        </div>
        <Money value={o.amount} tone={o.isOutflow ? 'expense' : 'income'} className="font-semibold" />
      </button>
    </li>
  );
}

function GoalCard({ goal, accountName, onEdit }: { goal: Goal; accountName?: string; onEdit: () => void }) {
  const [delta, setDelta] = useState('');
  const contribute = useWrite(async (sign: 1 | -1) => {
    const v = parseAmount(delta);
    if (v === null || v <= 0) throw new Error('Enter an amount.');
    await goalsRepo.contribute(goal, sign * v);
  }, [keys.goals]);
  const monthly = goal.requiredMonthlyContribution();

  return (
    <Card as="li">
      <button type="button" onClick={onEdit} className="block w-full text-left" aria-label={`Edit ${goal.name}`}>
        <Eyebrow>{goal.targetDate ? `Target ${dateLong(goal.targetDate)}` : 'No target date'}</Eyebrow>
        <div className="mt-1 flex items-baseline justify-between gap-2">
          <h3 className="truncate font-semibold">{goal.name}</h3>
          <span className="text-sm text-ink-muted">{Math.round(goal.progress * 100)}%</span>
        </div>
        <div
          className="mt-2 h-2 overflow-hidden rounded-full bg-track"
          role="progressbar"
          aria-valuenow={Math.round(goal.progress * 100)}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-label={`${goal.name} progress`}
        >
          <div className="h-full rounded-full bg-protected" style={{ width: `${goal.progress * 100}%` }} />
        </div>
        <p className="mt-2 text-sm">
          {formatMoney(goal.savedAmount)} saved of {formatMoney(goal.targetAmount)}
          {accountName && <span className="text-ink-muted"> · in {accountName}</span>}
        </p>
        <p className="mt-1 text-xs text-ink-muted">
          {goal.isComplete
            ? 'Funded. It stays out of safe-to-spend until you spend it.'
            : monthly !== null
              ? `${formatMoney(monthly)} a month keeps this on time.`
              : 'Counted as protected, so it never shows as safe to spend.'}
        </p>
      </button>
      <form
        className="mt-4 flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          contribute.mutate(1, { onSuccess: () => setDelta('') });
        }}
      >
        <Input
          inputMode="decimal"
          placeholder="Amount"
          value={delta}
          onChange={(e) => setDelta(e.target.value)}
          aria-label={`Amount to add to ${goal.name}`}
        />
        <Button type="submit" variant="secondary" busy={contribute.isPending}>
          Add
        </Button>
        <Button type="button" variant="ghost" onClick={() => contribute.mutate(-1, { onSuccess: () => setDelta('') })}>
          Take out
        </Button>
      </form>
      {contribute.error && <p className="mt-2 text-xs text-expense">{contribute.error.message}</p>}
    </Card>
  );
}

function ObligationDialog({
  value,
  accounts,
  onClose,
}: {
  value: Obligation | 'new' | null;
  accounts: Account[];
  onClose: () => void;
}) {
  const existing = value && value !== 'new' ? value : null;
  const [direction, setDirectionRaw] = useState<ObligationDirection>(existing?.direction ?? 'out');
  const [name, setName] = useState(existing?.name ?? '');
  const [amount, setAmount] = useState(existing ? String(existing.amount) : '');
  const [cadence, setCadence] = useState<Cadence>(existing?.cadence ?? 'monthly');
  const [nextDue, setNextDue] = useState(() => (existing ? toIsoDate(existing.nextDue) : toIsoDate(addDays(today(), 1))));
  const [accountId, setAccountId] = useState(existing?.accountId ?? '');
  const [category, setCategory] = useState(existing?.category ?? '');
  const [isActive, setIsActive] = useState(existing?.isActive ?? true);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const categories = useCategoryNames(direction === 'in' ? 'income' : 'expense');

  // Switching direction clears the category, as in the app.
  const setDirection = (d: ObligationDirection) => {
    setDirectionRaw(d);
    setCategory('');
  };

  const save = useWrite(async () => {
    const amt = parseAmount(amount);
    if (!name.trim()) throw new Error('Name it — Rent, Salary…');
    if (amt === null || amt <= 0) throw new Error('Enter an amount');
    const due = tryParseDate(nextDue);
    if (!due) throw new Error('Pick when it next lands.');
    const fields = {
      name: name.trim(),
      amount: amt,
      nextDue: due,
      direction,
      cadence,
      accountId: accountId || null,
      category: category || null,
    };
    if (existing) await obligationsRepo.update(existing.id, { ...fields, isActive });
    else await obligationsRepo.create(fields);
  }, [keys.obligations]);

  const remove = useWrite(async () => {
    if (existing) await obligationsRepo.remove(existing.id);
  }, [keys.obligations]);

  const max = toIsoDate(addMonths(today(), 60));

  return (
    <>
      <Dialog
        open={value !== null && !confirmDelete}
        onClose={onClose}
        title={existing ? 'Edit commitment' : 'New commitment'}
      >
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            save.mutate(undefined, { onSuccess: onClose });
          }}
        >
          <Segmented<ObligationDirection>
            label="Direction"
            value={direction}
            onChange={setDirection}
            options={[
              { value: 'out', label: 'Bill' },
              { value: 'in', label: 'Income' },
            ]}
          />
          <Field label="What is it">
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={direction === 'out' ? 'Rent' : 'Salary'}
              autoFocus
            />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Amount (GHS)">
              <Input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
            </Field>
            <Field label="Repeats">
              <Select value={cadence} onChange={(e) => setCadence(e.target.value as Cadence)}>
                {CADENCES.map((c) => (
                  <option key={c.value} value={c.value}>
                    {c.label}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Next due" hint="When does it next land?">
              <Input type="date" min="2000-01-01" max={max} value={nextDue} onChange={(e) => setNextDue(e.target.value)} />
            </Field>
            <Field label={direction === 'out' ? 'Leaves from' : 'Lands in'}>
              <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                <option value="">Any account</option>
                {accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
          {categories.length > 0 && (
            <Field label="Category">
              <Select value={category} onChange={(e) => setCategory(e.target.value)}>
                <option value="">None</option>
                {categories.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </Select>
            </Field>
          )}
          <p className="text-xs text-ink-faint">
            {direction === 'out'
              ? 'Pinning it to an account is what lets the app warn you when that account cannot cover it.'
              : 'The next due date sets the horizon for safe-to-spend.'}
          </p>
          {existing && (
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
              Active (paused ones are ignored by safe-to-spend)
            </label>
          )}
          <ErrorNote error={save.error} />
          <div className="flex justify-between gap-2 pt-2">
            {existing ? (
              <Button type="button" variant="ghost" onClick={() => setConfirmDelete(true)}>
                <Icon name="trash" width={16} height={16} /> Delete
              </Button>
            ) : (
              <span />
            )}
            <Button type="submit" busy={save.isPending}>
              Save
            </Button>
          </div>
        </form>
      </Dialog>
      <Confirm
        open={confirmDelete}
        title={`Delete "${existing?.name ?? ''}"?`}
        body={`${formatMoney(existing?.amount ?? 0)} stops being held back, so your safe-to-spend goes up by that much. Your balances do not change.`}
        confirmLabel="Delete"
        danger
        busy={remove.isPending}
        error={remove.error}
        onClose={() => setConfirmDelete(false)}
        onConfirm={() => remove.mutate(undefined, { onSuccess: onClose })}
      />
    </>
  );
}

function GoalDialog({
  value,
  accounts,
  nextPriority,
  onClose,
}: {
  value: Goal | 'new' | null;
  accounts: Account[];
  nextPriority: number;
  onClose: () => void;
}) {
  const existing = value && value !== 'new' ? value : null;
  const [name, setName] = useState(existing?.name ?? '');
  const [target, setTarget] = useState(existing ? String(existing.targetAmount) : '');
  const [saved, setSaved] = useState(existing ? existing.savedAmount.toFixed(2) : '0.00');
  const [targetDate, setTargetDate] = useState(() =>
    existing ? (existing.targetDate ? toIsoDate(existing.targetDate) : '') : toIsoDate(addDays(today(), 90)),
  );
  const [accountId, setAccountId] = useState(existing?.accountId ?? '');
  const [priority, setPriority] = useState(String(existing?.priority ?? nextPriority));
  const [isActive, setIsActive] = useState(existing?.isActive ?? true);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const save = useWrite(async () => {
    const t = parseAmount(target);
    const s = parseAmount(saved);
    if (!name.trim()) throw new Error('Name the goal');
    if (t === null || t <= 0) throw new Error('Set a target');
    if (s === null || s < 0) throw new Error('Saved must be zero or more');
    const fields = {
      name: name.trim(),
      targetAmount: t,
      savedAmount: s,
      targetDate: targetDate ? parseDate(targetDate) : null,
      accountId: accountId || null,
      priority: Number(priority) || 0,
    };
    if (existing) await goalsRepo.update(existing.id, { ...fields, isActive });
    else await goalsRepo.create(fields);
  }, [keys.goals]);

  const remove = useWrite(async () => {
    if (existing) await goalsRepo.remove(existing.id);
  }, [keys.goals]);

  return (
    <>
      <Dialog open={value !== null && !confirmDelete} onClose={onClose} title={existing ? 'Edit goal' : 'New goal'}>
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            save.mutate(undefined, { onSuccess: onClose });
          }}
        >
          <Field label="Goal">
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Laptop" autoFocus />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Target (GHS)">
              <Input inputMode="decimal" value={target} onChange={(e) => setTarget(e.target.value)} />
            </Field>
            <Field label="Saved">
              <Input inputMode="decimal" value={saved} onChange={(e) => setSaved(e.target.value)} />
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Target date" hint={targetDate ? undefined : 'None'}>
              <div className="flex gap-1">
                <Input type="date" value={targetDate} onChange={(e) => setTargetDate(e.target.value)} />
                {targetDate && (
                  <Button type="button" variant="ghost" onClick={() => setTargetDate('')} aria-label="Clear target date">
                    ✕
                  </Button>
                )}
              </div>
            </Field>
            <Field label="Priority" hint="Lower comes first.">
              <Input inputMode="numeric" value={priority} onChange={(e) => setPriority(e.target.value)} />
            </Field>
          </div>
          {accounts.length > 0 && (
            <Field label="Held in">
              <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                <option value="">Any account</option>
                {accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </Select>
            </Field>
          )}
          <p className="text-xs text-ink-faint">
            A goal is held back from safe-to-spend, so the money stops looking available.
          </p>
          {existing && (
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
              Active
            </label>
          )}
          <ErrorNote error={save.error} />
          <div className="flex justify-between gap-2 pt-2">
            {existing ? (
              <Button type="button" variant="ghost" onClick={() => setConfirmDelete(true)}>
                <Icon name="trash" width={16} height={16} /> Delete
              </Button>
            ) : (
              <span />
            )}
            <Button type="submit" busy={save.isPending}>
              Save
            </Button>
          </div>
        </form>
      </Dialog>
      <Confirm
        open={confirmDelete}
        title={`Delete "${existing?.name ?? ''}"?`}
        body={`The ${formatMoney(existing?.savedAmount ?? 0)} held for it goes back into safe-to-spend. Your balances do not change.`}
        confirmLabel="Delete"
        danger
        busy={remove.isPending}
        error={remove.error}
        onClose={() => setConfirmDelete(false)}
        onConfirm={() => remove.mutate(undefined, { onSuccess: onClose })}
      />
    </>
  );
}
