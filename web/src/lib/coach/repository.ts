'use client';

/** Port of insights/data/coach_repository.dart — threads live on the backend. */

import { apiFetch } from '../api/client';
import { type PendingMessage } from './service';
import { actionToJson, messageFromRow, type CoachMessage } from './types';

export interface ThreadSummary {
  id: string;
  title: string | null;
  updatedAt: Date;
  preview: string | null;
}

export const coachRepo = {
  /** The thread to continue — the most recently active one, as in the app. */
  async currentThreadId(): Promise<string> {
    const res = await apiFetch<{ id: string }>('/coach/threads/current');
    return res.id;
  },

  async startNewThread(): Promise<string> {
    const res = await apiFetch<{ id: string }>('/coach/threads', { method: 'POST' });
    return res.id;
  },

  async messages(threadId: string): Promise<CoachMessage[]> {
    const rows = await apiFetch<Record<string, unknown>[]>(`/coach/threads/${threadId}/messages`);
    return rows.map(messageFromRow);
  },

  /** The backend stamps each row a strictly later created_at, in order. */
  async saveTurn(threadId: string, messages: PendingMessage[]): Promise<void> {
    if (messages.length === 0) return;
    await apiFetch(`/coach/threads/${threadId}/messages`, {
      method: 'POST',
      body: {
        messages: messages.map((m) => ({
          role: m.role,
          content: m.content ?? null,
          tool_calls: m.toolCalls ?? null,
          tool_call_id: m.toolCallId ?? null,
          name: m.name ?? null,
          actions: m.actions && m.actions.length > 0 ? m.actions.map(actionToJson) : null,
        })),
      },
    });
  },

  async clearThread(threadId: string): Promise<void> {
    await apiFetch(`/coach/threads/${threadId}`, { method: 'DELETE' });
  },

  /** Brings a thread back to the top so the coach resumes it. */
  async touchThread(threadId: string): Promise<void> {
    await apiFetch(`/coach/threads/${threadId}/touch`, { method: 'POST' });
  },

  /** Past conversations, newest first, with the first question as a preview. */
  async threads(): Promise<ThreadSummary[]> {
    const rows = await apiFetch<
      { id: string; title: string | null; updated_at: string; preview: string | null }[]
    >('/coach/threads');
    return rows.map((r) => ({
      id: r.id,
      title: r.title,
      updatedAt: new Date(r.updated_at),
      preview: r.preview,
    }));
  },

  async deleteLegacyChat(id: string): Promise<void> {
    await apiFetch(`/coach/chats/${id}`, { method: 'DELETE' });
  },

  async clearLegacyChats(): Promise<void> {
    await apiFetch('/coach/chats', { method: 'DELETE' });
  },

  /** Legacy single-shot answers from before coach threads existed (ai_chats). */
  async legacyChats(): Promise<{ id: string; question: string; answer: string; createdAt: Date }[]> {
    const rows = await apiFetch<
      { id: string; question: string; answer: string; created_at: string }[]
    >('/coach/chats', { query: { limit: '50' } });
    return rows.map((r) => ({
      id: r.id,
      question: r.question,
      answer: r.answer,
      createdAt: new Date(r.created_at),
    }));
  },
};
