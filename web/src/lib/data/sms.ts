'use client';

/**
 * The SMS import data the web can manage — port of the backend half of
 * sms/data/sms_import_repository.dart. Reading the inbox itself needs the
 * Android app; everything here is plain tables and endpoints.
 */

import { apiFetch } from '../api/client';
import { toIsoDate, type DateOnly } from '../dates';

/** bank_sms_parser.dart kBankSmsParsers — ids, names and identifier hints. */
export const SMS_PARSERS = [
  { id: 'mtn_momo', name: 'MTN MoMo', hint: 'Your MoMo number as alerts write it, e.g. 0244123456' },
  { id: 'fidelity', name: 'Fidelity Bank', hint: 'Masked account number as alerts write it, e.g. 1234' },
  { id: 'access', name: 'Access Bank', hint: 'Masked account number as alerts write it, e.g. 0912' },
  { id: 'cbg', name: 'CBG', hint: 'Masked account number as alerts write it, e.g. 0045' },
] as const;

export interface SmsLink {
  id: string;
  parserId: string;
  accountId: string;
  identifiers: string[];
}

export interface ParsedSms {
  parser_id?: string;
  verdict?: string;
  direction?: 'credit' | 'debit' | string;
  amount?: number;
  fee?: number;
  balance?: number;
  counterparty?: string;
  reference?: string;
  summary?: string;
}

export interface InboxItem {
  id: string;
  sender: string;
  body: string;
  receivedAt: Date;
  status: 'pending' | 'unparsed';
  parsed: ParsedSms | null;
  dedupeKey: string | null;
}

export interface RoutingRule {
  id: string;
  parserId: string | null;
  matchText: string;
  txnType: 'Income' | 'Expense' | 'Transfer';
  category: string | null;
  counterpartAccountId: string | null;
}

type Row = Record<string, unknown>;

export const smsRepo = {
  async links(): Promise<SmsLink[]> {
    const rows = await apiFetch<Row[]>('/sms/links');
    return rows.map((r) => ({
      id: String(r.id),
      parserId: String(r.parser_id),
      accountId: String(r.account_id),
      identifiers: (r.identifiers as string[] | null) ?? [],
    }));
  },

  async saveLink(parserId: string, accountId: string, identifiers: string[]): Promise<void> {
    await apiFetch('/sms/links', {
      method: 'PUT',
      body: { parser_id: parserId, account_id: accountId, identifiers },
    });
  },

  async removeLink(id: string): Promise<void> {
    await apiFetch(`/sms/links/${id}`, { method: 'DELETE' });
  },

  async reviewQueue(): Promise<InboxItem[]> {
    const rows = await apiFetch<Row[]>('/sms/inbox', { query: { limit: '60' } });
    return rows.map((r) => ({
      id: String(r.id),
      sender: String(r.sender),
      body: String(r.body),
      receivedAt: new Date(String(r.received_at)),
      status: r.status === 'unparsed' ? 'unparsed' : 'pending',
      parsed: (r.parsed as ParsedSms | null) ?? null,
      dedupeKey: (r.dedupe_key as string | null) ?? null,
    }));
  },

  async reviewCount(): Promise<number> {
    const res = await apiFetch<{ count: number }>('/sms/inbox/count');
    return res.count ?? 0;
  },

  /** "Not money" — no confirmation, as in the app. */
  async ignore(id: string): Promise<void> {
    await apiFetch(`/sms/inbox/${id}/ignore`, { method: 'POST' });
  },

  /**
   * Turns a reviewed message into a transaction, atomically, via the same
   * endpoint and the same txn shape the app sends (PlannedTxn.toJson).
   */
  async resolve(
    item: InboxItem,
    t: {
      accountId: string;
      toAccountId: string | null;
      type: 'Income' | 'Expense' | 'Transfer';
      amount: number;
      category: string | null;
      date: DateOnly;
    },
    remember: { parserId: string; counterparty: string } | null,
  ): Promise<void> {
    await apiFetch(`/sms/inbox/${item.id}/resolve`, {
      method: 'POST',
      body: {
        txn: {
          account_id: t.accountId,
          to_account_id: t.type === 'Transfer' ? (t.toAccountId ?? '') : '',
          type: t.type,
          amount: t.amount,
          category: t.type === 'Transfer' ? 'Transfer' : t.category,
          description: item.parsed?.summary ?? '',
          date: toIsoDate(t.date),
          external_ref: item.dedupeKey ?? `review|${item.id}|${t.amount.toFixed(2)}`,
        },
      },
    });
    if (remember && remember.counterparty.trim()) {
      await apiFetch('/sms/rules', {
        method: 'POST',
        body: {
          parser_id: remember.parserId,
          match_text: remember.counterparty,
          match_kind: 'contains',
          txn_type: t.type,
          category: t.type === 'Transfer' ? null : t.category,
          counterpart_account_id: t.type === 'Transfer' ? t.toAccountId : null,
        },
      });
    }
  },

  async rules(): Promise<RoutingRule[]> {
    const rows = await apiFetch<Row[]>('/sms/rules');
    return rows.map((r) => ({
      id: String(r.id),
      parserId: (r.parser_id as string | null) ?? null,
      matchText: String(r.match_text),
      txnType: r.txn_type as RoutingRule['txnType'],
      category: (r.category as string | null) ?? null,
      counterpartAccountId: (r.counterpart_account_id as string | null) ?? null,
    }));
  },

  async removeRule(id: string): Promise<void> {
    await apiFetch(`/sms/rules/${id}`, { method: 'DELETE' });
  },
};
