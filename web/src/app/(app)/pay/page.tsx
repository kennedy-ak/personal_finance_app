'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import {
  Button,
  Card,
  Empty,
  ErrorNote,
  Eyebrow,
  Field,
  Input,
  Loading,
  Money,
  Select,
  cx,
  parseAmount,
} from '@/components/ui';
import { MONEY_KEYS, useCategoryNames, useMoney, useWrite } from '@/lib/data/hooks';
import { transactionsRepo } from '@/lib/data/repositories';
import { today } from '@/lib/dates';
import { type MoneySnapshot } from '@/lib/finance/money-engine';
import { planPayment } from '@/lib/finance/payment-planner';
import { formatMoney } from '@/lib/format';
import { plural } from '@/lib/present';

/** Port of payments/presentation/pay_screen.dart. */
export default function PayPage() {
  const router = useRouter();
  const money = useMoney();
  const categories = useCategoryNames('expense');
  const [amount, setAmount] = useState('');
  const [payFrom, setPayFrom] = useState('');
  const [pickedCategory, setCategory] = useState('');
  const [note, setNote] = useState('');
  const [recorded, setRecorded] = useState<string | null>(null);

  // Default 'Other', falling back to the first when it is hidden.
  const category = categories.includes(pickedCategory)
    ? pickedCategory
    : categories.includes('Other')
      ? 'Other'
      : (categories[0] ?? 'Other');

  const value = parseAmount(amount) ?? 0;
  const plan =
    money.ready && value > 0
      ? planPayment({ amount: value, snapshot: money.snapshot, obligations: money.obligations, payFromAccountId: payFrom || null })
      : null;

  const record = useWrite(async () => {
    if (!plan || !plan.isPossible) return;
    const d = today();
    for (const t of plan.transfers) {
      await transactionsRepo.createTransfer({
        fromAccountId: t.from.id,
        toAccountId: t.to.id,
        amount: Math.round(t.amount * 100) / 100,
        description: note.trim() ? `To cover: ${note.trim()}` : 'To cover a payment',
        date: d,
      });
    }
    for (const s of plan.sources) {
      await transactionsRepo.create({
        accountId: s.account.id,
        type: 'Expense',
        amount: Math.round(s.amount * 100) / 100,
        category,
        description: note.trim() || null,
        date: d,
      });
    }
  }, MONEY_KEYS);

  if (!money.ready) return money.error ? <ErrorNote error={money.error} /> : <Loading />;

  const { snapshot: s, accounts } = money;
  const live = accounts.filter((a) => !a.isArchived);
  const source = plan?.sources[0];
  const balanceNow = source?.account.balance ?? 0;

  return (
    <div className="mx-auto max-w-2xl pb-24">
      <button type="button" onClick={() => router.back()} className="mb-3 text-sm text-ink-muted hover:text-ink">
        ← Back
      </button>
      <h1 className="text-2xl font-semibold tracking-tight">Where should this come from?</h1>
      <p className="mt-1 text-sm text-ink-muted">
        {value > 0 ? `${note.trim() || 'Payment'} · ${formatMoney(value)}` : 'Nothing entered yet'}
      </p>

      {recorded && (
        <p role="status" className="mt-4 rounded-xl border border-income-border bg-income-surface px-4 py-3 text-sm text-income">
          Recorded {recorded}.
        </p>
      )}

      <Card className="mt-5 space-y-4">
        <Field label="Amount (GHS)">
          <Input
            inputMode="decimal"
            placeholder="0.00"
            value={amount}
            onChange={(e) => {
              setAmount(e.target.value);
              setRecorded(null);
            }}
            className="h-14 text-2xl font-semibold"
            autoFocus
          />
        </Field>
        <Field label="It has to leave from">
          <Select value={payFrom} onChange={(e) => setPayFrom(e.target.value)}>
            <option value="">Anywhere — you decide</option>
            {live.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </Select>
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Category">
            <Select value={category} onChange={(e) => setCategory(e.target.value)}>
              {categories.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="What is it for?">
            <Input placeholder="Sending to Kwame" value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
        </div>
      </Card>

      {!plan ? (
        <div className="mt-4">
          <Empty title="Enter an amount">Type what you need to send and this works out where it should come from.</Empty>
        </div>
      ) : plan.isPossible ? (
        <>
          <Card className="mt-4">
            <Eyebrow>{plan.transfers.length ? 'Move it first' : plan.isSplit ? 'Split it' : 'Pay from'}</Eyebrow>
            <h2 className="mt-1 text-lg font-semibold">{plan.headline}</h2>
            {source?.caution && <p className="mt-1 text-sm text-warning">{source.caution}</p>}
            {plan.transfers.map((t) => (
              <p key={t.from.id} className="mt-2 text-sm">
                {t.from.name} → {t.to.name} · <Money value={t.amount} className="font-medium" />
              </p>
            ))}
            {plan.isSplit &&
              plan.sources.map((x) => (
                <p key={x.account.id} className="mt-1 text-sm">
                  {x.account.name} · <Money value={x.amount} className="font-medium" />
                  {x.caution && <span className="text-ink-muted"> — {x.caution}</span>}
                </p>
              ))}
            {!plan.isSplit && source && (
              <div className="mt-4 grid grid-cols-2 gap-3 rounded-xl bg-recessed p-3 text-sm">
                <div>
                  <div className="text-xs text-ink-muted">Balance now</div>
                  <Money value={balanceNow} className="font-semibold" />
                </div>
                <div>
                  <div className="text-xs text-ink-muted">After paying</div>
                  <Money
                    value={balanceNow + plan.transfers.reduce((a, t) => a + t.amount, 0) - value}
                    className="font-semibold"
                  />
                </div>
              </div>
            )}
            <p className={cx('mt-4 text-sm', plan.impact.causesShortfall ? 'text-expense' : 'text-ink-body')}>
              Leaves {formatMoney(plan.impact.safeToSpendAfter)} spendable
              {plan.impact.runwayDaysAfter !== null && ` — about ${Math.floor(plan.impact.runwayDaysAfter)} days of cash`}
              {plan.impact.daysUntilIncome !== null && `, with income in ${plan.impact.daysUntilIncome} days`}.
              {plan.impact.causesShortfall && ' You would run short before payday.'}
            </p>
          </Card>

          {plan.reasoning.length > 0 && (
            <Card className="mt-4">
              <h3 className="mb-2 text-sm font-semibold">Why not the others</h3>
              <ul className="space-y-1.5 text-sm text-ink-muted">
                {plan.reasoning.map((r) => (
                  <li key={r}>{r}</li>
                ))}
              </ul>
            </Card>
          )}

          <ErrorNote error={record.error} />
          <div className="mt-6">
            <Button
              className="h-12 w-full"
              busy={record.isPending}
              onClick={() =>
                record.mutate(undefined, {
                  onSuccess: () => {
                    setRecorded(formatMoney(value));
                    setAmount('');
                    setNote('');
                  },
                })
              }
            >
              {plan.transfers.length ? 'Move the money and record it' : 'Record this payment'}
            </Button>
            <p className="mt-2 text-center text-xs text-ink-faint">
              {plan.transfers.length
                ? `Logs ${plural(plan.transfers.length, 'transfer')} and the payment.`
                : 'Logs the payment against the account above.'}
            </p>
          </div>
        </>
      ) : (
        <Refusal value={value} s={s} headline={plan.headline} onSmaller={() => setAmount('')} />
      )}
    </div>
  );
}

function Refusal({
  value,
  s,
  headline,
  onSmaller,
}: {
  value: number;
  s: MoneySnapshot;
  headline: string;
  onSmaller: () => void;
}) {
  const free = Math.max(0, s.usableCash);
  const tied = [
    ['Floors on your accounts', s.floors],
    ['Money held for goals', s.goalReserve],
    ['Reserved accounts', s.reserved],
    ['Locked accounts', s.locked],
  ] as const;
  return (
    <>
      <Card className="mt-4 border-expense-border bg-expense-surface">
        <h2 className="text-lg font-semibold text-expense">No account can do this</h2>
        <p className="mt-1 text-sm text-expense">
          You hold {formatMoney(s.totalBalance)}, but only {formatMoney(free)} of it is free. This payment is{' '}
          {formatMoney(Math.max(0, value - free))} short.
        </p>
        <div className="mt-4 grid grid-cols-2 gap-3 text-sm">
          <div>
            <div className="text-xs opacity-80">Free to use</div>
            <Money value={free} className="font-semibold" />
          </div>
          <div>
            <div className="text-xs opacity-80">Short by</div>
            <Money value={Math.max(0, value - free)} className="font-semibold" />
          </div>
        </div>
        <p className="mt-3 text-sm">{headline}</p>
      </Card>
      <Card className="mt-4">
        <h3 className="text-sm font-semibold">If you release a hold</h3>
        <p className="mt-1 text-sm text-ink-muted">
          Floors and goals are your own rules. Loosen one and this payment may become possible.
        </p>
        <Link href="/plan" className="mt-3 inline-block text-sm font-medium text-brand-ink hover:underline">
          Review those holds
        </Link>
      </Card>
      <Card className="mt-4">
        <h3 className="mb-2 text-sm font-semibold">Where the money is tied up</h3>
        <dl className="divide-y divide-rule text-sm">
          {tied.map(([k, v]) => (
            <div key={k} className="flex justify-between py-2">
              <dt className="text-ink-muted">{k}</dt>
              <dd>
                <Money value={v} />
              </dd>
            </div>
          ))}
        </dl>
      </Card>
      <Button variant="secondary" className="mt-6 h-12 w-full" onClick={onSmaller}>
        Try a smaller amount
      </Button>
    </>
  );
}
