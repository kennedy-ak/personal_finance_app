'use client';

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import Markdown from 'react-markdown';
import { Icon } from '@/components/icons';
import { Button, Confirm, Dialog, Empty, ErrorNote, Eyebrow, Loading, SectionTitle } from '@/components/ui';
import { coachRepo } from '@/lib/coach/repository';

type Legacy = { id: string; question: string; answer: string; createdAt: Date };

function stamp(d: Date) {
  const day = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const diff = Math.round((day(new Date()) - day(d)) / 86_400_000);
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Yesterday';
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

/**
 * Port of insights/presentation/ai_history_screen.dart (the legacy ai_chats
 * answers, with copy/delete/clear all), plus the coach threads, which the web
 * can reopen.
 */
export default function AiHistoryPage() {
  const router = useRouter();
  const qc = useQueryClient();
  const threads = useQuery({ queryKey: ['coach', 'threads'], queryFn: coachRepo.threads });
  const legacy = useQuery({ queryKey: ['coach', 'legacy'], queryFn: coachRepo.legacyChats, retry: false });
  const [open, setOpen] = useState<Legacy | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [confirmClear, setConfirmClear] = useState(false);
  const [copied, setCopied] = useState(false);

  const resume = useMutation({
    mutationFn: async (id: string) => {
      await coachRepo.touchThread(id);
      return id;
    },
    onSuccess: (id) => {
      qc.setQueryData(['coach', 'thread'], id);
      router.push('/insights');
    },
  });
  const removeThread = useMutation({
    mutationFn: coachRepo.clearThread,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['coach'] }),
  });
  const removeLegacy = useMutation({
    mutationFn: coachRepo.deleteLegacyChat,
    onSuccess: () => {
      setConfirmDelete(false);
      setOpen(null);
      return qc.invalidateQueries({ queryKey: ['coach', 'legacy'] });
    },
  });
  const clearLegacy = useMutation({
    mutationFn: coachRepo.clearLegacyChats,
    onSuccess: () => {
      setConfirmClear(false);
      return qc.invalidateQueries({ queryKey: ['coach', 'legacy'] });
    },
  });

  if (threads.isLoading || legacy.isLoading) return <Loading />;
  if (threads.error) return <ErrorNote error={threads.error} />;

  const conversations = (threads.data ?? []).filter((t) => t.preview);
  const answers = legacy.data ?? [];

  return (
    <div className="mx-auto max-w-3xl">
      <header className="mb-6 flex items-end justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">Older conversations</h1>
        {answers.length > 0 && (
          <Button variant="ghost" onClick={() => setConfirmClear(true)}>
            Clear all
          </Button>
        )}
      </header>
      <ErrorNote error={resume.error ?? removeThread.error} />

      {conversations.length === 0 && answers.length === 0 && (
        <Empty title="No past conversations">
          Questions you ask the coach are kept here so you can go back to what it told you.
        </Empty>
      )}

      {conversations.length > 0 && (
        <section className="mb-8">
          <SectionTitle>Coach chats</SectionTitle>
          <ul className="divide-y divide-rule rounded-2xl border border-hairline bg-card">
            {conversations.map((t) => (
              <li key={t.id} className="flex items-center gap-3 px-4 py-3">
                <button type="button" onClick={() => resume.mutate(t.id)} className="min-w-0 flex-1 text-left">
                  <Eyebrow>{stamp(t.updatedAt)}</Eyebrow>
                  <div className="truncate text-sm font-medium">{t.title || t.preview}</div>
                </button>
                <Button
                  variant="ghost"
                  aria-label="Delete conversation"
                  busy={removeThread.isPending && removeThread.variables === t.id}
                  onClick={() => removeThread.mutate(t.id)}
                >
                  <Icon name="trash" width={16} height={16} />
                </Button>
              </li>
            ))}
          </ul>
        </section>
      )}

      {answers.length > 0 && (
        <section>
          <SectionTitle>Earlier answers</SectionTitle>
          <ul className="divide-y divide-rule rounded-2xl border border-hairline bg-card">
            {answers.map((c) => (
              <li key={c.id}>
                <button type="button" onClick={() => setOpen(c)} className="block w-full px-4 py-3 text-left hover:bg-recessed">
                  <Eyebrow>{stamp(c.createdAt)}</Eyebrow>
                  <div className="line-clamp-2 text-sm font-medium">{c.question}</div>
                  <div className="mt-0.5 text-xs text-ink-muted">
                    {c.answer.split(/\s+/).filter(Boolean).length} words ·{' '}
                    {c.createdAt.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }).toLowerCase()}
                  </div>
                </button>
              </li>
            ))}
          </ul>
          <p className="mt-3 text-xs text-ink-faint">Conversations stay here until you clear them. Clearing is permanent.</p>
        </section>
      )}

      <Dialog open={open !== null && !confirmDelete} onClose={() => setOpen(null)} title={open ? open.createdAt.toLocaleDateString('en-GB', { dateStyle: 'long' }) : ''}>
        {open && (
          <div className="space-y-4 text-sm">
            <p className="rounded-2xl bg-brand px-4 py-3 text-on-brand">{open.question}</p>
            <div className="space-y-2 select-text [&_li]:ml-4 [&_ul]:list-disc">
              <Markdown>{open.answer}</Markdown>
            </div>
            <div className="flex justify-between gap-2">
              <Button variant="ghost" onClick={() => setConfirmDelete(true)}>
                Delete
              </Button>
              <Button
                variant="secondary"
                onClick={async () => {
                  await navigator.clipboard.writeText(open.answer);
                  setCopied(true);
                  setTimeout(() => setCopied(false), 1500);
                }}
              >
                {copied ? 'Copied' : 'Copy answer'}
              </Button>
            </div>
          </div>
        )}
      </Dialog>
      <Confirm
        open={confirmDelete}
        title="Delete this conversation?"
        body="It is removed on every device. This cannot be undone."
        confirmLabel="Delete"
        danger
        busy={removeLegacy.isPending}
        error={removeLegacy.error}
        onClose={() => setConfirmDelete(false)}
        onConfirm={() => open && removeLegacy.mutate(open.id)}
      />
      <Confirm
        open={confirmClear}
        title="Clear every conversation?"
        body="Every earlier answer is removed on every device. This cannot be undone."
        confirmLabel="Clear all"
        danger
        busy={clearLegacy.isPending}
        error={clearLegacy.error}
        onClose={() => setConfirmClear(false)}
        onConfirm={() => clearLegacy.mutate()}
      />
    </div>
  );
}
