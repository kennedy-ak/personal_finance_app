/**
 * Ports of insights/domain/coach_action.dart and coach_message.dart.
 * The JSON shapes are what the Flutter app stores in ai_messages, so a thread
 * started on the phone continues on the web and vice versa.
 */

import { parseDate, toIsoDate, type DateOnly } from '../dates';
import { cadenceFromValue, type Cadence, type ObligationDirection } from '../domain/obligation';

// --- Actions: proposals awaiting a tap. Nothing here has happened. ---------

export interface TransferAction {
  type: 'transfer';
  fromAccountId: string;
  fromAccountName: string;
  toAccountId: string;
  toAccountName: string;
  amount: number;
  reason: string;
}

export interface CommitmentAction {
  type: 'commitment';
  name: string;
  amount: number;
  direction: ObligationDirection;
  cadence: Cadence;
  nextDue: DateOnly;
  accountId: string | null;
  accountName: string | null;
}

export type CoachAction = TransferAction | CommitmentAction;

export function actionToJson(a: CoachAction): Record<string, unknown> {
  if (a.type === 'transfer') {
    return {
      type: 'transfer',
      from_account_id: a.fromAccountId,
      from_account_name: a.fromAccountName,
      to_account_id: a.toAccountId,
      to_account_name: a.toAccountName,
      amount: a.amount,
      reason: a.reason,
    };
  }
  return {
    type: 'commitment',
    name: a.name,
    amount: a.amount,
    direction: a.direction,
    cadence: a.cadence,
    // Dart's DateTime.toIso8601String() on a local-midnight date.
    next_due: `${toIsoDate(a.nextDue)}T00:00:00.000`,
    account_id: a.accountId,
    account_name: a.accountName,
  };
}

export function actionFromJson(j: Record<string, unknown>): CoachAction | null {
  try {
    if (j.type === 'transfer') {
      return {
        type: 'transfer',
        fromAccountId: String(j.from_account_id),
        fromAccountName: String(j.from_account_name),
        toAccountId: String(j.to_account_id),
        toAccountName: String(j.to_account_name),
        amount: Number(j.amount),
        reason: (j.reason as string | null) ?? '',
      };
    }
    if (j.type === 'commitment') {
      return {
        type: 'commitment',
        name: String(j.name),
        amount: Number(j.amount),
        direction: j.direction === 'in' ? 'in' : 'out',
        cadence: cadenceFromValue(j.cadence as string | null),
        nextDue: parseDate(String(j.next_due)),
        accountId: (j.account_id as string | null) ?? null,
        accountName: (j.account_name as string | null) ?? null,
      };
    }
  } catch {
    // A malformed stored action is dropped rather than breaking the thread.
  }
  return null;
}

// --- Messages ---------------------------------------------------------------

export type CoachRole = 'user' | 'assistant' | 'tool';

/** Provider-shaped tool call, kept verbatim so threads replay exactly. */
export interface ToolCall {
  id: string;
  type?: string;
  function: { name: string; arguments: string };
  [k: string]: unknown;
}

export interface CoachMessage {
  id: string;
  threadId: string;
  role: CoachRole;
  /** Null on an assistant turn that only requested tools. */
  content: string | null;
  toolCalls?: ToolCall[] | null;
  toolCallId?: string | null;
  name?: string | null;
  actions?: CoachAction[];
  createdAt: Date;
}

/** Something the user should see, as opposed to bookkeeping the model needs. */
export function isVisible(m: CoachMessage): boolean {
  return m.role === 'user' || (m.role === 'assistant' && (m.content?.trim().length ?? 0) > 0);
}

export type WireMessage = Record<string, unknown>;

/** The shape the provider expects when replaying history. */
export function toProviderJson(m: CoachMessage): WireMessage {
  switch (m.role) {
    case 'user':
      return { role: 'user', content: m.content ?? '' };
    case 'assistant':
      return {
        role: 'assistant',
        content: m.content,
        ...(m.toolCalls && m.toolCalls.length > 0 ? { tool_calls: m.toolCalls } : {}),
      };
    case 'tool':
      return { role: 'tool', tool_call_id: m.toolCallId ?? '', content: m.content ?? '' };
  }
}

export function messageFromRow(j: Record<string, unknown>): CoachMessage {
  const role = j.role === 'user' || j.role === 'tool' ? j.role : 'assistant';
  const rawActions = Array.isArray(j.actions) ? j.actions : [];
  return {
    id: String(j.id),
    threadId: String(j.thread_id),
    role,
    content: (j.content as string | null) ?? null,
    toolCalls: Array.isArray(j.tool_calls) ? (j.tool_calls as ToolCall[]) : null,
    toolCallId: (j.tool_call_id as string | null) ?? null,
    name: (j.name as string | null) ?? null,
    actions: rawActions
      .filter((a): a is Record<string, unknown> => typeof a === 'object' && a !== null)
      .map(actionFromJson)
      .filter((a): a is CoachAction => a !== null),
    createdAt: new Date(String(j.created_at)),
  };
}
