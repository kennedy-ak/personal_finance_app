'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Icon } from '@/components/icons';
import {
  Button,
  Card,
  Dialog,
  ErrorNote,
  Eyebrow,
  Field,
  Input,
  Loading,
  Money,
  SectionTitle,
  Segmented,
  Select,
  parseAmount,
} from '@/components/ui';
import { keys, useAccounts, useCategoryNames } from '@/lib/data/hooks';
import { SMS_PARSERS, smsRepo, type InboxItem, type SmsLink } from '@/lib/data/sms';
import { parseDate, toIsoDate, tryParseDate } from '@/lib/dates';
import { type Account } from '@/lib/domain/account';
import { dayMonth, timeOfDay } from '@/lib/format';

const SMS_KEYS = { links: ['sms', 'links'], queue: ['sms', 'queue'], rules: ['sms', 'rules'] } as const;

/**
 * Port of sms/presentation/sms_import_screen.dart. Scanning the inbox needs
 * the Android app; linking senders, reviewing what it could not place, and
 * managing learned rules all work here.
 */
export default function SmsImportPage() {
  const qc = useQueryClient();
  const accountsQ = useAccounts();
  const links = useQuery({ queryKey: SMS_KEYS.links, queryFn: smsRepo.links });
  const queue = useQuery({ queryKey: SMS_KEYS.queue, queryFn: smsRepo.reviewQueue });
  const rules = useQuery({ queryKey: SMS_KEYS.rules, queryFn: smsRepo.rules });
  const [linking, setLinking] = useState<(typeof SMS_PARSERS)[number] | null>(null);
  const [reviewing, setReviewing] = useState<InboxItem | null>(null);

  const ignore = useMutation({
    mutationFn: smsRepo.ignore,
    onSuccess: () => qc.invalidateQueries({ queryKey: SMS_KEYS.queue }),
  });
  const removeRule = useMutation({
    mutationFn: smsRepo.removeRule,
    onSuccess: () => qc.invalidateQueries({ queryKey: SMS_KEYS.rules }),
  });

  if (links.isLoading || queue.isLoading || rules.isLoading || accountsQ.isLoading) return <Loading />;
  const err = links.error ?? queue.error ?? rules.error ?? accountsQ.error;
  if (err) return <ErrorNote error={err} />;

  const accounts = (accountsQ.data ?? []).filter((a) => !a.isArchived);
  const name = (id: string | null) => accountsQ.data?.find((a) => a.id === id)?.name ?? 'unknown account';
  const linkFor = (parserId: string) => links.data?.find((l) => l.parserId === parserId);
  const items = queue.data ?? [];

  return (
    <div className="mx-auto max-w-3xl space-y-8">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">SMS import</h1>
        <p className="mt-1 text-sm text-ink-muted">Alerts become records without typing them.</p>
      </header>

      <div className="rounded-2xl border border-info-border bg-info-surface p-4 text-sm text-info">
        Reading messages happens in the Android app (“Scan messages now”). Here you can choose which senders it reads,
        review what it could not place, and manage the rules it has learned.
      </div>

      <section>
        <SectionTitle>Senders</SectionTitle>
        <ul className="divide-y divide-rule rounded-2xl border border-hairline bg-card">
          {SMS_PARSERS.map((p) => {
            const l = linkFor(p.id);
            return (
              <li key={p.id}>
                <button
                  type="button"
                  onClick={() => setLinking(p)}
                  className="flex w-full items-center justify-between px-4 py-3 text-left hover:bg-recessed"
                >
                  <span>
                    <span className="block text-sm font-medium">{p.name}</span>
                    <span className="text-xs text-ink-muted">{l ? `Records into ${name(l.accountId)}` : 'Not linked'}</span>
                  </span>
                  <Icon name="arrowRight" width={16} height={16} className="text-ink-faint" />
                </button>
              </li>
            );
          })}
        </ul>
      </section>

      <section>
        <SectionTitle>Needs review · {items.length}</SectionTitle>
        <ErrorNote error={ignore.error} />
        {items.length === 0 ? (
          <p className="rounded-2xl border border-dashed border-outline p-6 text-center text-sm text-ink-muted">
            Nothing waiting. Scan your inbox and anything the rules can’t place lands here.
          </p>
        ) : (
          <ul className="space-y-2">
            {items.map((it) => (
              <Card as="li" key={it.id} className="p-4">
                <div className="flex items-baseline justify-between gap-2">
                  <Eyebrow>
                    {it.sender} · {dayMonth(new Date(Date.UTC(it.receivedAt.getFullYear(), it.receivedAt.getMonth(), it.receivedAt.getDate())))} ·{' '}
                    {timeOfDay(it.receivedAt)}
                  </Eyebrow>
                  {it.parsed?.amount != null && <Money value={it.parsed.amount} className="font-semibold" />}
                </div>
                <p className="mt-1 font-medium">
                  {it.status === 'unparsed' ? 'Could not read this message' : (it.parsed?.summary ?? 'Needs a category')}
                </p>
                <p className="mt-1 line-clamp-4 text-sm text-ink-muted">{it.body}</p>
                <div className="mt-3 flex gap-2">
                  <Button variant="secondary" onClick={() => setReviewing(it)} disabled={!it.parsed}>
                    Review
                  </Button>
                  <Button variant="ghost" busy={ignore.isPending && ignore.variables === it.id} onClick={() => ignore.mutate(it.id)}>
                    Not money
                  </Button>
                </div>
              </Card>
            ))}
          </ul>
        )}
      </section>

      <section>
        <SectionTitle>Learned rules</SectionTitle>
        <ErrorNote error={removeRule.error} />
        {(rules.data ?? []).length === 0 ? (
          <p className="text-sm text-ink-muted">
            Rules are learned when you tick ‘remember’ while reviewing. After that, the same payee imports itself.
          </p>
        ) : (
          <ul className="divide-y divide-rule rounded-2xl border border-hairline bg-card">
            {rules.data!.map((r) => (
              <li key={r.id} className="flex items-center gap-3 px-4 py-3">
                <span className="flex-1">
                  <span className="block text-sm font-medium">{r.matchText}</span>
                  <span className="text-xs text-ink-muted">
                    {r.txnType === 'Transfer' ? `Transfer · ${name(r.counterpartAccountId)}` : `${r.txnType} · ${r.category}`}
                  </span>
                </span>
                <Button variant="ghost" aria-label={`Delete rule ${r.matchText}`} onClick={() => removeRule.mutate(r.id)}>
                  <Icon name="trash" width={16} height={16} />
                </Button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <LinkDialog
        key={linking?.id ?? 'closed'}
        parser={linking}
        link={linking ? linkFor(linking.id) : undefined}
        accounts={accounts}
        onClose={() => setLinking(null)}
      />
      <ReviewDialog
        key={reviewing?.id ?? 'closed'}
        item={reviewing}
        links={links.data ?? []}
        accounts={accounts}
        onClose={() => setReviewing(null)}
      />
    </div>
  );
}

function LinkDialog({
  parser,
  link,
  accounts,
  onClose,
}: {
  parser: (typeof SMS_PARSERS)[number] | null;
  link?: SmsLink;
  accounts: Account[];
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const [accountId, setAccountId] = useState(link?.accountId ?? '');
  const [identifiers, setIdentifiers] = useState(link?.identifiers.join(', ') ?? '');
  const save = useMutation({
    mutationFn: () =>
      smsRepo.saveLink(
        parser!.id,
        accountId,
        identifiers.split(',').map((s) => s.trim()).filter(Boolean),
      ),
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: SMS_KEYS.links });
      onClose();
    },
  });
  const remove = useMutation({
    mutationFn: () => smsRepo.removeLink(link!.id),
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: SMS_KEYS.links });
      onClose();
    },
  });

  return (
    <Dialog open={parser !== null} onClose={onClose} title={parser?.name ?? ''}>
      <div className="space-y-4">
        <p className="text-sm text-ink-muted">
          Every alert from this sender that scans pick up is recorded into the linked account.
        </p>
        <Field label="Records into">
          <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="">Pick an account</option>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Your identifiers (optional)" hint={parser?.hint}>
          <Input value={identifiers} onChange={(e) => setIdentifiers(e.target.value)} placeholder="Comma-separated" />
        </Field>
        <ErrorNote error={save.error ?? remove.error} />
        <div className="flex justify-between gap-2">
          {link ? (
            <Button variant="ghost" busy={remove.isPending} onClick={() => remove.mutate()}>
              Stop importing this sender
            </Button>
          ) : (
            <span />
          )}
          <Button disabled={!accountId} busy={save.isPending} onClick={() => save.mutate()}>
            {accountId ? 'Save' : 'Pick an account'}
          </Button>
        </div>
      </div>
    </Dialog>
  );
}

function ReviewDialog({
  item,
  links,
  accounts,
  onClose,
}: {
  item: InboxItem | null;
  links: SmsLink[];
  accounts: Account[];
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const parsed = item?.parsed ?? null;
  const from = links.find((l) => l.parserId === parsed?.parser_id);
  const guessed = parsed?.direction === 'credit' ? 'Income' : 'Expense';
  const [type, setType] = useState<'Expense' | 'Income' | 'Transfer'>(guessed);
  const [amount, setAmount] = useState(parsed?.amount != null ? String(parsed.amount) : '');
  const [date, setDate] = useState(() =>
    item ? toIsoDate(new Date(Date.UTC(item.receivedAt.getFullYear(), item.receivedAt.getMonth(), item.receivedAt.getDate()))) : '',
  );
  const [toAccountId, setToAccountId] = useState('');
  const [pickedCategory, setCategory] = useState('');
  const categories = useCategoryNames(type === 'Income' ? 'income' : 'expense');
  const category = categories.includes(pickedCategory) ? pickedCategory : '';
  const counterparty = parsed?.counterparty?.trim() ?? '';
  const [remember, setRemember] = useState(Boolean(counterparty));

  const value = parseAmount(amount) ?? 0;
  const canSave =
    Boolean(from) && value > 0 && (type === 'Transfer' ? Boolean(toAccountId) : Boolean(category)) && Boolean(tryParseDate(date));

  const save = useMutation({
    mutationFn: () =>
      smsRepo.resolve(
        item!,
        {
          accountId: from!.accountId,
          toAccountId: type === 'Transfer' ? toAccountId : null,
          type,
          amount: value,
          category: type === 'Transfer' ? null : category,
          date: parseDate(date),
        },
        remember && counterparty && parsed?.parser_id ? { parserId: parsed.parser_id, counterparty } : null,
      ),
    onSuccess: async () => {
      await Promise.all(
        [SMS_KEYS.queue, SMS_KEYS.rules, keys.transactions, keys.accounts].map((k) => qc.invalidateQueries({ queryKey: k })),
      );
      onClose();
    },
  });

  return (
    <Dialog open={item !== null} onClose={onClose} title="Review message">
      {item && (
        <div className="space-y-4">
          <p className="rounded-xl bg-recessed p-3 text-sm text-ink-muted">{item.body}</p>
          {!from && (
            <ErrorNote error={`Link ${SMS_PARSERS.find((p) => p.id === parsed?.parser_id)?.name ?? 'this sender'} to an account first.`} />
          )}
          <div className="grid grid-cols-2 gap-3">
            <Field label="Amount (GHS)">
              <Input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
            </Field>
            <Field label="Date">
              <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </Field>
          </div>
          <div>
            <span className="mb-1.5 block text-xs font-medium text-ink-muted">What happened</span>
            <Segmented
              label="What happened"
              value={type}
              onChange={(t) => {
                setType(t);
                setCategory('');
              }}
              options={[
                { value: 'Expense', label: 'Expense' },
                { value: 'Income', label: 'Income' },
                { value: 'Transfer', label: 'Transfer' },
              ]}
            />
          </div>
          {type === 'Transfer' ? (
            <Field label="To account">
              <Select value={toAccountId} onChange={(e) => setToAccountId(e.target.value)}>
                <option value="">Pick an account</option>
                {accounts
                  .filter((a) => a.id !== from?.accountId)
                  .map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
              </Select>
            </Field>
          ) : (
            <Field label="Category">
              <Select value={category} onChange={(e) => setCategory(e.target.value)}>
                <option value="">Pick a category</option>
                {categories.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </Select>
            </Field>
          )}
          {counterparty && (
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
              Remember {counterparty} — next time this imports itself
            </label>
          )}
          <ErrorNote error={save.error} />
          <Button className="w-full" disabled={!canSave} busy={save.isPending} onClick={() => save.mutate()}>
            Add to records
          </Button>
        </div>
      )}
    </Dialog>
  );
}
