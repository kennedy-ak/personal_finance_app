import { expect, type BrowserContext, type Page } from '@playwright/test';
import { E2E } from './env';

/**
 * Test-side access to the FastAPI backend. There is no service role anymore:
 * every check runs as the user themself, holding the token their signup
 * returned — which is also a quiet assertion that the API scopes rows
 * correctly, since a leak would surface as unexpected rows here.
 */

const tokens = new Map<string, string>();

async function apiCall<T>(
  token: string | null,
  method: string,
  path: string,
  body?: unknown,
): Promise<T> {
  const res = await fetch(`${E2E.apiUrl}${path}`, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const detail = (data as { detail?: unknown })?.detail;
    throw new Error(`${method} ${path} → ${res.status}: ${JSON.stringify(detail ?? data)}`);
  }
  return data as T;
}

export function tokenFor(userId: string): string {
  const t = tokens.get(userId);
  if (!t) throw new Error(`No token recorded for user ${userId}`);
  return t;
}

/** Call the backend as a previously created/signed-in test user. */
export function apiAs<T = unknown>(
  userId: string,
  method: string,
  path: string,
  body?: unknown,
): Promise<T> {
  return apiCall<T>(tokenFor(userId), method, path, body);
}

/** A fresh throwaway user per run, so tests never depend on leftovers. */
export function testIdentity(tag: string) {
  const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  return {
    email: `e2e-${tag}-${id}@example.com`,
    password: `E2e-${id}-pw!`,
    name: `E2E ${tag}`,
  };
}

interface AuthResponse {
  token: string;
  user: { id: string; email: string; full_name: string | null };
}

export async function createConfirmedUser(tag: string) {
  const who = testIdentity(tag);
  const res = await apiCall<AuthResponse>(null, 'POST', '/auth/signup', {
    email: who.email,
    password: who.password,
    full_name: who.name,
  });
  tokens.set(res.user.id, res.token);
  return { ...who, id: res.user.id };
}

/** Logs in through the API (not the UI) and records the token for `rows()`. */
export async function signInApi(email: string, password: string) {
  const res = await apiCall<AuthResponse>(null, 'POST', '/auth/login', { email, password });
  tokens.set(res.user.id, res.token);
  return { id: res.user.id, fullName: res.user.full_name };
}

/** Marks the welcome screen as seen, the way tapping through it does. */
export async function skipWelcome(context: BrowserContext) {
  await context.addCookies([{ name: 'seen_splash', value: '1', url: E2E.baseURL }]);
}

export async function signIn(page: Page, email: string, password: string) {
  await skipWelcome(page.context());
  await page.goto('/login');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password', { exact: true }).fill(password);
  await page.getByRole('button', { name: 'Log in' }).click();
  await page.waitForURL((u) => u.pathname === '/');
  await expect(page.getByTestId('safe-to-spend')).toBeVisible();
}

const TABLE_PATHS: Record<string, string> = {
  accounts: '/accounts',
  transactions: '/transactions',
  categories: '/categories',
  obligations: '/obligations',
  goals: '/goals',
  sms_account_links: '/sms/links',
  sms_routing_rules: '/sms/rules',
  sms_inbox: '/sms/inbox?status=all&limit=500',
  ai_threads: '/coach/threads',
};

/** Reads rows as the user — the ground truth behind the UI. */
export async function rows<T = Record<string, unknown>>(table: string, userId: string): Promise<T[]> {
  if (table === 'ai_messages') {
    const threads = await apiAs<{ id: string }[]>(userId, 'GET', '/coach/threads');
    const all: T[] = [];
    for (const t of threads) {
      all.push(...(await apiAs<T[]>(userId, 'GET', `/coach/threads/${t.id}/messages`)));
    }
    return all;
  }
  const path = TABLE_PATHS[table];
  if (!path) throw new Error(`rows(): no endpoint mapped for table ${table}`);
  return apiAs<T[]>(userId, 'GET', path);
}

export async function accountByName(userId: string, name: string) {
  const list = await rows<{ id: string; name: string; balance: number; opening_balance: number }>('accounts', userId);
  const a = list.find((x) => x.name === name);
  if (!a) throw new Error(`No account ${name}`);
  return { ...a, balance: Number(a.balance), opening_balance: Number(a.opening_balance) };
}

/** Seeds the review queue the way the Android scan writes it. */
export async function seedInboxHold(
  userId: string,
  item: {
    sender: string;
    body: string;
    receivedAt: string;
    dedupeKey: string;
    parsed: Record<string, unknown> | null;
  },
) {
  await apiAs(userId, 'POST', '/sms/hold', {
    sender: item.sender,
    body: item.body,
    received_at: item.receivedAt,
    dedupe_key: item.dedupeKey,
    parsed: item.parsed,
  });
}

/** Local YYYY-MM-DD, offset by whole days. */
export const iso = (offsetDays: number) => {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
