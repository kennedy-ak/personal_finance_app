'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, type FormEvent } from 'react';
import { CategoryEditor } from '@/components/category-editor';
import { Icon } from '@/components/icons';
import {
  Button,
  Card,
  Empty,
  ErrorNote,
  Field,
  Input,
  Loading,
  Segmented,
  Select,
  parseAmount,
} from '@/components/ui';
import { QUICK_ADDS } from '@/lib/constants';
import { MONEY_KEYS, useAccounts, useCategoryNames, useTodayIso, useWrite } from '@/lib/data/hooks';
import { transactionsRepo } from '@/lib/data/repositories';
import { kindLabel } from '@/lib/domain/account';
import { tryParseDate } from '@/lib/dates';
import { type TxnType } from '@/lib/domain/transaction';
import { formatMoney } from '@/lib/format';
import { relativeDate } from '@/lib/present';

/** Port of transactions/presentation/add_transaction_screen.dart. */
export default function AddTransactionPage() {
  const router = useRouter();
  const { data: allAccounts, isLoading, error: loadError } = useAccounts();
  const accounts = (allAccounts ?? []).filter((a) => !a.isArchived);

  const [type, setTypeRaw] = useState<TxnType>('Expense');
  const [amount, setAmount] = useState('');
  const [pickedAccountId, setAccountId] = useState('');
  const [pickedToAccountId, setToAccountId] = useState('');
  const [pickedCategory, setCategory] = useState('');
  const todayIso = useTodayIso();
  const [pickedDate, setDate] = useState('');
  const date = pickedDate || todayIso;
  const [description, setDescription] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [newCategory, setNewCategory] = useState(false);

  const categories = useCategoryNames(type === 'Income' ? 'income' : 'expense');

  // Switching type resets the category, as in the app.
  const setType = (t: TxnType) => {
    setTypeRaw(t);
    setCategory('');
  };

  // Defaults are derived, so they follow the lists as they load.
  const accountId = pickedAccountId || accounts[0]?.id || '';
  const toAccountId =
    pickedToAccountId && pickedToAccountId !== accountId
      ? pickedToAccountId
      : (accounts.find((a) => a.id !== accountId)?.id ?? '');
  const category = categories.includes(pickedCategory) ? pickedCategory : (categories[0] ?? '');
  const source = accounts.find((a) => a.id === accountId);

  const save = useWrite(async () => {
    const value = parseAmount(amount);
    if (value === null || value <= 0) throw new Error('Enter an amount');
    const d = tryParseDate(date);
    if (!d) throw new Error('Pick a date.');

    if (type === 'Transfer') {
      if (!accountId || !toAccountId) throw new Error('Pick both accounts.');
      if (accountId === toAccountId) throw new Error('Pick two different accounts.');
      if (source && source.balance < value) {
        throw new Error(`${source.name} only holds ${formatMoney(source.balance)}.`);
      }
      await transactionsRepo.createTransfer({
        fromAccountId: accountId,
        toAccountId,
        amount: value,
        description: description.trim() || null,
        date: d,
      });
    } else {
      if (!accountId) throw new Error('Pick the account it came from.');
      if (!category) throw new Error('Pick a category.');
      await transactionsRepo.create({
        accountId,
        type,
        amount: value,
        category,
        description: description.trim() || null,
        date: d,
      });
    }
  }, MONEY_KEYS);

  function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    save.mutate(undefined, {
      onSuccess: () => router.push('/history'),
      onError: (err) => setError(err.message),
    });
  }

  if (isLoading) return <Loading />;
  if (loadError) return <ErrorNote error={loadError} />;

  const header = (
    <div className="mb-6 flex items-center justify-between">
      <button type="button" onClick={() => router.back()} className="text-sm text-ink-muted hover:text-ink">
        Cancel
      </button>
      <h1 className="text-lg font-semibold">New transaction</h1>
      <span className="w-12" />
    </div>
  );

  if (accounts.length === 0) {
    return (
      <div className="mx-auto max-w-lg">
        {header}
        <Empty title="No accounts yet">
          <p>A transaction has to come from somewhere. Add the account you paid from first.</p>
          <Link href="/accounts" className="mt-3 inline-block font-medium text-brand-ink hover:underline">
            Add an account
          </Link>
        </Empty>
      </div>
    );
  }

  const parsedDate = tryParseDate(date);
  const accountOption = (a: (typeof accounts)[number]) => (
    <option key={a.id} value={a.id}>
      {a.name} · {kindLabel(a.kind)} · {formatMoney(a.balance)}
    </option>
  );

  return (
    <div className="mx-auto max-w-lg">
      {header}
      <Card>
        <form onSubmit={submit} className="space-y-5">
          <Field label="Amount (GHS)">
            <Input
              inputMode="decimal"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="h-14 text-2xl font-semibold"
              autoFocus
            />
          </Field>

          <Segmented<TxnType>
            label="Transaction type"
            value={type}
            onChange={setType}
            options={[
              { value: 'Expense', label: 'Expense' },
              { value: 'Income', label: 'Income' },
              { value: 'Transfer', label: 'Transfer' },
            ]}
          />

          {type === 'Expense' && (
            <div className="flex flex-wrap gap-2">
              {QUICK_ADDS.map((q) => (
                <button
                  key={q.label}
                  type="button"
                  onClick={() => {
                    setAmount(String(q.amount));
                    setCategory(q.category);
                  }}
                  className="rounded-full border border-hairline bg-recessed px-3 py-1 text-xs text-ink-body hover:border-outline"
                >
                  {q.label} · {formatMoney(q.amount)}
                </button>
              ))}
            </div>
          )}

          {type === 'Transfer' ? (
            <>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="From">
                  <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                    {accounts.map(accountOption)}
                  </Select>
                </Field>
                <Field label="To">
                  <Select value={toAccountId} onChange={(e) => setToAccountId(e.target.value)}>
                    {accounts.filter((a) => a.id !== accountId).map(accountOption)}
                  </Select>
                </Field>
              </div>
              <p className="rounded-xl border border-info-border bg-info-surface px-3 py-2 text-sm text-info">
                A transfer does not change your total balance. It moves{' '}
                {formatMoney(parseAmount(amount) ?? 0)} into an account you can spend from.
              </p>
            </>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="Account">
                <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                  {accounts.map(accountOption)}
                </Select>
              </Field>
              <div>
                <div className="mb-1.5 flex items-center justify-between">
                  <label htmlFor="category" className="text-xs font-medium text-ink-muted">
                    Category
                  </label>
                  <button
                    type="button"
                    onClick={() => setNewCategory(true)}
                    className="flex items-center gap-1 text-xs font-medium text-brand-ink hover:underline"
                  >
                    <Icon name="plus" width={12} height={12} /> New
                  </button>
                </div>
                <Select id="category" value={category} onChange={(e) => setCategory(e.target.value)}>
                  {categories.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </Select>
              </div>
            </div>
          )}

          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Date" hint={parsedDate ? relativeDate(parsedDate) : undefined}>
              <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} max="2100-12-31" />
            </Field>
            <Field label="Note (optional)">
              <Input
                placeholder="Melcom"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
              />
            </Field>
          </div>

          <ErrorNote error={error} />

          <Button type="submit" busy={save.isPending} className="h-12 w-full">
            {type === 'Transfer' ? 'Save transfer' : type === 'Income' ? 'Save income' : 'Save expense'}
          </Button>
        </form>
      </Card>

      <CategoryEditor
        key={newCategory ? `new-${type}` : 'closed'}
        open={newCategory}
        kind={type === 'Income' ? 'income' : 'expense'}
        onClose={() => setNewCategory(false)}
        onSaved={(n) => setCategory(n)}
      />
    </div>
  );
}

