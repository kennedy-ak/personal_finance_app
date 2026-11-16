'use client';

import { useQuery, useQueryClient } from '@tanstack/react-query';
import Link from 'next/link';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import Markdown from 'react-markdown';
import { coachRepo } from '@/lib/coach/repository';
import { CoachService } from '@/lib/coach/service';
import { suggestionsFor, TOOL_LABELS } from '@/lib/coach/suggestions';
import { CoachContext } from '@/lib/coach/tools';
import { EdgeFunctionTransport } from '@/lib/coach/transport';
import { isVisible, type CoachAction, type CoachMessage } from '@/lib/coach/types';
import { keys, useMoney } from '@/lib/data/hooks';
import { obligationsRepo, transactionsRepo } from '@/lib/data/repositories';
import { today } from '@/lib/dates';
import { cadenceLabel } from '@/lib/domain/obligation';
import { dateLong, formatMoney } from '@/lib/format';
import { plural } from '@/lib/present';
import { Icon } from './icons';
import { Button, Confirm, ErrorNote, Eyebrow, Loading, cx } from './ui';

/** Port of insights/presentation/ask_ai_tab.dart. */
export function CoachChat({ onBack }: { onBack: () => void }) {
  const qc = useQueryClient();
  const money = useMoney();
  const [input, setInput] = useState('');
  const [pending, setPending] = useState<string | null>(null);
  const [toolLabel, setToolLabel] = useState<string | null>(null);
  const [failed, setFailed] = useState<{ question: string; error: unknown } | null>(null);
  const [confirmNew, setConfirmNew] = useState(false);
  const bottom = useRef<HTMLDivElement>(null);

  const threadQ = useQuery({ queryKey: ['coach', 'thread'], queryFn: coachRepo.currentThreadId });
  const threadId = threadQ.data;
  const messagesQ = useQuery({
    queryKey: ['coach', 'messages', threadId],
    queryFn: () => coachRepo.messages(threadId!),
    enabled: Boolean(threadId),
  });
  const messages = messagesQ.data ?? [];
  const visible = messages.filter(isVisible);

  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }, [visible.length, pending, toolLabel]);

  async function ask(question: string) {
    const q = question.trim();
    if (!q || !threadId || !money.ready || pending) return;
    setInput('');
    setFailed(null);
    setPending(q);
    setToolLabel(null);
    try {
      const context = new CoachContext(
        money.snapshot,
        money.accounts.filter((a) => !a.isArchived),
        money.txns,
        money.obligations,
        money.goals,
      );
      const turn = await new CoachService(new EdgeFunctionTransport()).send(q, messages, context, (name) =>
        setToolLabel(TOOL_LABELS[name] ?? 'Thinking'),
      );
      await coachRepo.saveTurn(threadId, turn.messages);
      await qc.invalidateQueries({ queryKey: ['coach', 'messages', threadId] });
    } catch (e) {
      setFailed({ question: q, error: e });
    } finally {
      setPending(null);
      setToolLabel(null);
    }
  }

  async function newConversation() {
    const id = await coachRepo.startNewThread();
    qc.setQueryData(['coach', 'thread'], id);
    setFailed(null);
    setConfirmNew(false);
  }

  function submit(e: FormEvent) {
    e.preventDefault();
    void ask(input);
  }

  if (threadQ.isLoading || !money.ready) {
    return money.error || threadQ.error ? <ErrorNote error={money.error ?? threadQ.error} /> : <Loading />;
  }

  const empty = visible.length === 0 && !pending;
  const suggestions = suggestionsFor(money.snapshot, money.alerts, money.goals, money.obligations, money.accounts);
  const nCommitments = money.obligations.filter((o) => o.isActive).length;

  return (
    <div className="mx-auto flex max-w-3xl flex-col">
      <div className="mb-5 flex items-center justify-between">
        <button type="button" onClick={onBack} className="text-sm text-ink-muted hover:text-ink">
          ← Overview
        </button>
        <h1 className="text-lg font-semibold">Your coach</h1>
        {empty ? (
          <Link href="/ai-history" className="text-sm font-medium text-brand-ink hover:underline">
            History
          </Link>
        ) : (
          <button type="button" onClick={() => setConfirmNew(true)} className="text-sm font-medium text-brand-ink hover:underline">
            New chat
          </button>
        )}
      </div>

      <div className="space-y-4">
        {empty && (
          <>
            <div className="rounded-2xl border border-hairline bg-card p-5 text-sm text-ink-body">
              It reads the same numbers the dashboard does — your {plural(money.accounts.filter((a) => !a.isArchived).length, 'account')},{' '}
              {plural(nCommitments, 'commitment')}, this month&apos;s transactions. It can propose a transfer or a new bill, but
              nothing moves until you approve it.
            </div>
            <div className="flex flex-col gap-2">
              {suggestions.map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => ask(s)}
                  className="rounded-2xl border border-hairline bg-card px-4 py-3 text-left text-sm hover:border-outline"
                >
                  {s}
                </button>
              ))}
            </div>
          </>
        )}

        {visible.map((m) => (
          <Bubble key={m.id} message={m} />
        ))}

        {pending && (
          <>
            <Bubble message={{ id: 'p', threadId: '', role: 'user', content: pending, createdAt: new Date(0) }} />
            <div className="flex items-center gap-2 text-sm text-ink-muted" role="status">
              <span className="inline-flex gap-1">
                <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-ink-faint" />
                <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-ink-faint [animation-delay:120ms]" />
                <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-ink-faint [animation-delay:240ms]" />
              </span>
              {toolLabel ?? 'Thinking'}…
            </div>
          </>
        )}

        {failed && (
          <div role="alert" className="rounded-2xl border border-expense-border bg-expense-surface p-4 text-sm text-expense">
            <p className="font-medium">Could not reach the coach</p>
            <p className="mt-1">Your question was not sent, so nothing was charged. Your numbers are unchanged.</p>
            <p className="mt-1 text-xs opacity-80">{failed.error instanceof Error ? failed.error.message : String(failed.error)}</p>
            <Button variant="secondary" className="mt-3" onClick={() => ask(failed.question)}>
              Retry
            </Button>
          </div>
        )}
        <div ref={bottom} />
      </div>

      <form onSubmit={submit} className="sticky bottom-20 mt-6 flex items-end gap-2 rounded-2xl border border-hairline bg-card p-2 shadow-sm lg:bottom-6">
        <textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              void ask(input);
            }
          }}
          rows={1}
          placeholder="Ask about your money"
          aria-label="Message the coach"
          className="max-h-32 min-h-10 flex-1 resize-none bg-transparent px-3 py-2 text-sm outline-none placeholder:text-ink-faint"
          disabled={Boolean(pending)}
        />
        <Button type="submit" disabled={!input.trim()} busy={Boolean(pending)} aria-label="Send">
          <Icon name="send" width={16} height={16} />
        </Button>
      </form>

      <Confirm
        open={confirmNew}
        title="Start a new conversation?"
        body="The coach will forget what you have discussed so far. The old conversation stays in your history."
        confirmLabel="Start fresh"
        cancelLabel="Keep going"
        onClose={() => setConfirmNew(false)}
        onConfirm={newConversation}
      />
    </div>
  );
}

function Bubble({ message }: { message: CoachMessage }) {
  const mine = message.role === 'user';
  return (
    <div className={cx('flex flex-col', mine ? 'items-end' : 'items-start')}>
      <div
        className={cx(
          'max-w-[85%] rounded-2xl px-4 py-3 text-sm leading-relaxed',
          mine ? 'bg-brand text-on-brand' : 'border border-hairline bg-card text-ink-body',
        )}
      >
        {mine ? (
          <p className="whitespace-pre-wrap">{message.content}</p>
        ) : (
          <div className="space-y-2 [&_li]:ml-4 [&_ol]:list-decimal [&_strong]:text-ink [&_ul]:list-disc">
            <Markdown>{message.content ?? ''}</Markdown>
          </div>
        )}
      </div>
      {message.actions?.map((a, i) => <ActionCard key={i} action={a} />)}
    </div>
  );
}

/** Port of coach_action_card.dart — the only path from coach to a real record. */
function ActionCard({ action }: { action: CoachAction }) {
  const qc = useQueryClient();
  const [state, setState] = useState<'idle' | 'busy' | 'done' | 'dismissed'>('idle');
  const [error, setError] = useState(false);

  async function apply() {
    setState('busy');
    setError(false);
    try {
      if (action.type === 'transfer') {
        await transactionsRepo.createTransfer({
          fromAccountId: action.fromAccountId,
          toAccountId: action.toAccountId,
          amount: action.amount,
          description: action.reason,
          date: today(),
        });
        await Promise.all([keys.transactions, keys.accounts].map((k) => qc.invalidateQueries({ queryKey: k })));
      } else {
        await obligationsRepo.create({
          name: action.name,
          amount: action.amount,
          nextDue: action.nextDue,
          direction: action.direction,
          cadence: action.cadence,
          accountId: action.accountId,
        });
        await qc.invalidateQueries({ queryKey: keys.obligations });
      }
      setState('done');
    } catch {
      setError(true);
      setState('idle');
    }
  }

  if (state === 'dismissed') {
    return <p className="mt-2 text-xs text-ink-faint">Suggestion dismissed.</p>;
  }

  return (
    <div className="mt-2 w-full max-w-[85%] rounded-2xl border border-info-border bg-info-surface p-4 text-sm text-info">
      <Eyebrow className="text-current opacity-80">{state === 'done' ? 'Done' : 'Proposed · not yet done'}</Eyebrow>
      {action.type === 'transfer' ? (
        <>
          <div className="mt-1 font-medium">
            Move {formatMoney(action.amount)} from {action.fromAccountName} to {action.toAccountName}
          </div>
          {action.reason && <p className="mt-1 opacity-90">{action.reason}</p>}
        </>
      ) : (
        <>
          <div className="mt-1 font-medium">
            Record {action.direction === 'out' ? 'bill' : 'income'}: {action.name} — {formatMoney(action.amount)}
          </div>
          <p className="mt-1 opacity-90">
            {cadenceLabel(action.cadence)}, next {dateLong(action.nextDue)}
            {action.accountName && ` · ${action.accountName}`}
          </p>
        </>
      )}
      {state !== 'done' && (
        <div className="mt-3 flex items-center gap-2">
          <Button onClick={apply} busy={state === 'busy'}>
            {action.type === 'transfer' ? 'Approve transfer' : 'Save it'}
          </Button>
          <Button variant="ghost" onClick={() => setState('dismissed')}>
            Dismiss
          </Button>
        </div>
      )}
      {error && <p className="mt-2 text-expense">That did not go through, and nothing was changed. Try again.</p>}
    </div>
  );
}
