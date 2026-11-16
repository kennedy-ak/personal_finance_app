'use client';

/**
 * The only way the web app reaches the model: POST /coach/complete on the
 * FastAPI backend (the Edge Function's successor). The server holds the
 * OpenAI key and checks the caller's token.
 *
 * There is deliberately no direct-key fallback here — a key in the browser is
 * a key anyone can read.
 */

import { ApiError, apiFetch } from '../api/client';
import { CoachError, type CoachTransport } from './service';
import { type WireMessage } from './types';

export class ServerCoachTransport implements CoachTransport {
  async complete(
    messages: WireMessage[],
    tools: unknown[] | null,
    extra?: { temperature?: number; max_tokens?: number },
  ): Promise<Record<string, unknown>> {
    let data: unknown;
    try {
      data = await apiFetch('/coach/complete', {
        method: 'POST',
        body: { messages, ...(tools ? { tools } : {}), ...extra },
      });
    } catch (e) {
      if (e instanceof ApiError && e.status === 0) {
        throw new CoachError('Could not reach the coach. Check that the backend is running.');
      }
      throw new CoachError(e instanceof Error ? e.message : String(e));
    }
    return firstMessage(data);
  }
}

/** The old name, kept so existing imports keep working. */
export { ServerCoachTransport as EdgeFunctionTransport };

/** Pulls `choices[0].message` out of an OpenAI chat completion. */
function firstMessage(data: unknown): Record<string, unknown> {
  const choices = (data as { choices?: unknown })?.choices;
  if (!Array.isArray(choices) || choices.length === 0) {
    throw new CoachError('The coach returned an unexpected response.');
  }
  const message = (choices[0] as { message?: unknown }).message;
  if (!message || typeof message !== 'object') {
    throw new CoachError('The coach returned an unexpected response.');
  }
  return message as Record<string, unknown>;
}
