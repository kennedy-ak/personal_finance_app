/**
 * Port of insights/data/coach_service.dart — the agent loop. Tools run here,
 * in the browser, against the money engine; the Edge Function only relays.
 */

import { dateLong } from '../format';
import { COACH_TOOLS, runCoachTool, type CoachContext } from './tools';
import {
  toProviderJson,
  type CoachAction,
  type CoachMessage,
  type CoachRole,
  type ToolCall,
  type WireMessage,
} from './types';

/** How a request reaches the model. Swapped out wholesale in tests. */
export interface CoachTransport {
  complete(messages: WireMessage[], tools: unknown[] | null): Promise<Record<string, unknown>>;
}

export class CoachError extends Error {}

/** A message produced but not yet written to the database. */
export interface PendingMessage {
  role: CoachRole;
  content?: string | null;
  toolCalls?: ToolCall[] | null;
  toolCallId?: string | null;
  name?: string | null;
  actions?: CoachAction[];
}

export interface CoachTurn {
  messages: PendingMessage[];
  reply: string;
  actions: CoachAction[];
  toolsUsed: string[];
}

/** Rounds of tool calls before insisting on an answer. */
export const MAX_TOOL_ROUNDS = 5;

/** Past messages replayed. */
export const HISTORY_WINDOW = 24;

/**
 * Turns a stored thread into a message list the provider will accept: a tool
 * group is replayed only when every call it made has a matching result, and
 * anything else is reduced to the prose the model actually said.
 */
export function replayHistory(history: CoachMessage[]): WireMessage[] {
  const windowed = windowOf(history);
  const out: WireMessage[] = [];

  let i = 0;
  while (i < windowed.length) {
    const m = windowed[i];

    if (m.role === 'user') {
      out.push(toProviderJson(m));
      i++;
      continue;
    }

    // A tool result on its own answers a call that is not here.
    if (m.role === 'tool') {
      i++;
      continue;
    }

    const calls = m.toolCalls;
    if (!calls || calls.length === 0) {
      if ((m.content ?? '').trim()) out.push(toProviderJson(m));
      i++;
      continue;
    }

    let j = i + 1;
    const replies: CoachMessage[] = [];
    while (j < windowed.length && windowed[j].role === 'tool') {
      replies.push(windowed[j]);
      j++;
    }

    const asked = new Set(calls.map((c) => c.id ?? ''));
    const answered = new Set(replies.map((r) => r.toolCallId ?? ''));
    const complete = asked.size > 0 && [...asked].every((id) => answered.has(id));

    if (complete) {
      out.push(toProviderJson(m));
      for (const r of replies) if (asked.has(r.toolCallId ?? '')) out.push(toProviderJson(r));
    } else if ((m.content ?? '').trim()) {
      // Half a group: keep what the coach said, drop the bookkeeping.
      out.push({ role: 'assistant', content: m.content });
    }

    i = j;
  }

  return out;
}

/** The tail of the thread, cut forward to a turn boundary (a user message). */
function windowOf(history: CoachMessage[]): CoachMessage[] {
  if (history.length <= HISTORY_WINDOW) return history;
  let start = history.length - HISTORY_WINDOW;
  while (start < history.length && history[start].role !== 'user') start++;
  if (start >= history.length) return [];
  return history.slice(start);
}

export class CoachService {
  constructor(private readonly transport: CoachTransport) {}

  /**
   * `onTool` is told each tool's name just before it runs, so the UI can show
   * "Checking your position…" the way the app's thinking indicator does.
   */
  async send(
    question: string,
    history: CoachMessage[],
    context: CoachContext,
    onTool?: (name: string) => void,
  ): Promise<CoachTurn> {
    const produced: PendingMessage[] = [{ role: 'user', content: question }];
    const actions: CoachAction[] = [];
    const toolsUsed: string[] = [];

    const wire: WireMessage[] = [
      { role: 'system', content: systemPrompt(context) },
      ...replayHistory(history),
      { role: 'user', content: question },
    ];

    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      const isLastRound = round === MAX_TOOL_ROUNDS - 1;
      // On the final round, drop the tools so the model has to answer.
      const message = await this.transport.complete([...wire], isLastRound ? null : COACH_TOOLS);

      const calls = toolCallsFrom(message);
      const content = typeof message.content === 'string' ? message.content : null;

      if (calls.length === 0) {
        produced.push({ role: 'assistant', content, actions });
        return {
          messages: produced,
          reply: content?.trim()
            ? content.trim()
            : 'I could not put an answer together for that one. Try asking a different way.',
          actions,
          toolsUsed,
        };
      }

      produced.push({ role: 'assistant', content, toolCalls: calls });
      wire.push({ role: 'assistant', content, tool_calls: calls });

      for (const call of calls) {
        const name = call.function?.name ?? '';
        const id = call.id ?? '';
        onTool?.(name);
        const result = runCoachTool(name, decodeArgs(call.function?.arguments), context);
        toolsUsed.push(name);
        if (result.action) actions.push(result.action);

        produced.push({ role: 'tool', content: result.content, toolCallId: id, name });
        wire.push({ role: 'tool', tool_call_id: id, content: result.content });
      }
    }

    return {
      messages: produced,
      reply: 'That took more steps than I can manage in one go. Try asking something narrower.',
      actions,
      toolsUsed,
    };
  }
}

function systemPrompt(c: CoachContext): string {
  const names = c.accounts.map((a) => a.name).join(', ');
  return `You are the user's personal money manager. They are in Ghana and everything is in GHS.
Today is ${dateLong(c.snapshot.asOf)}.
Their accounts are: ${names || '(none set up yet)'}.

How to work:
- Call tools for every fact. Never calculate anything yourself and never estimate
  a balance, a total or a date — get_position, plan_payment and get_spending have
  already done the arithmetic, and their numbers are the only ones you may quote.
- For "where should I pay this from" or "can I afford this", always call
  plan_payment. Do not reason about which account to use on your own.
- When the answer is "move money from one account to another", call
  propose_transfer so the user gets a button instead of a paragraph.
- If the user mentions a bill or salary that is not in list_commitments, offer to
  record it with propose_commitment.
- propose_transfer and propose_commitment do NOT do anything. They show the user
  a card to approve. Never say something has been done, moved or saved.

How to talk:
- Like a sharp friend who handles money well. Short sentences. No preamble, no
  greeting, no sign-off.
- Under 150 words unless they asked for detail.
- Always end with the specific next step, naming the account and the amount.
- If the data is missing, say exactly what to add rather than guessing around it.
`;
}

function toolCallsFrom(message: Record<string, unknown>): ToolCall[] {
  const raw = message.tool_calls;
  if (!Array.isArray(raw)) return [];
  return raw.filter((c): c is ToolCall => typeof c === 'object' && c !== null);
}

/** Arguments arrive as a JSON string; malformed ones become {}. */
function decodeArgs(raw: unknown): Record<string, unknown> {
  if (raw && typeof raw === 'object') return raw as Record<string, unknown>;
  if (typeof raw !== 'string' || !raw.trim()) return {};
  try {
    const v = JSON.parse(raw);
    return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
  } catch {
    return {};
  }
}
