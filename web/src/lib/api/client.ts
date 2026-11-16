'use client';

/**
 * The one way the web app talks to the FastAPI backend — the replacement for
 * the Supabase client.
 *
 * The bearer token lives in localStorage; a marker cookie (`pf_signed_in`)
 * mirrors it so the proxy can redirect before a protected page ever renders.
 * The cookie carries no secret — it is an optimistic hint, exactly like the
 * old Supabase cookie check: a forged cookie gets you an empty shell whose
 * every API call answers 401.
 */

const TOKEN_KEY = 'pf_token';
const USER_KEY = 'pf_user';
export const SIGNED_IN_COOKIE = 'pf_signed_in';

/** Shaped like the old Supabase user where the pages read it. */
export interface ApiUser {
  id: string;
  email: string;
  user_metadata: { full_name?: string };
}

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function baseUrl(): string {
  return (process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8000').replace(/\/$/, '');
}

export function getToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

function toApiUser(raw: { id: string; email: string; full_name?: string | null }): ApiUser {
  return {
    id: raw.id,
    email: raw.email,
    user_metadata: raw.full_name ? { full_name: raw.full_name } : {},
  };
}

function storeSession(token: string, user: ApiUser): void {
  localStorage.setItem(TOKEN_KEY, token);
  localStorage.setItem(USER_KEY, JSON.stringify(user));
  document.cookie = `${SIGNED_IN_COOKIE}=1; path=/; max-age=${60 * 60 * 24 * 30}; samesite=lax`;
}

function clearSession(): void {
  try {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
  } catch {
    // storage unavailable — the cookie clear below still signs the shell out
  }
  document.cookie = `${SIGNED_IN_COOKIE}=; path=/; max-age=0; samesite=lax`;
}

/**
 * Fetch against the backend. Relative `path` (e.g. '/accounts'), optional
 * body (JSON-encoded) and query. Throws ApiError with the server's own
 * `detail` message on any non-2xx answer.
 */
export async function apiFetch<T = unknown>(
  path: string,
  init?: {
    method?: string;
    body?: unknown;
    query?: Record<string, string | undefined>;
  },
): Promise<T> {
  const url = new URL(baseUrl() + path);
  for (const [k, v] of Object.entries(init?.query ?? {})) {
    if (v !== undefined) url.searchParams.set(k, v);
  }

  const headers: Record<string, string> = { Accept: 'application/json' };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  if (init?.body !== undefined) headers['Content-Type'] = 'application/json';

  let res: Response;
  try {
    res = await fetch(url, {
      method: init?.method ?? 'GET',
      headers,
      body: init?.body === undefined ? undefined : JSON.stringify(init.body),
    });
  } catch {
    throw new ApiError(0, `Could not reach the server at ${baseUrl()}. Is the backend running?`);
  }

  if (res.status === 401 && token && path !== '/auth/login') {
    // Token expired or account gone — drop to login rather than failing
    // every query quietly.
    clearSession();
  }

  const text = await res.text();
  const data = text ? JSON.parse(text) : null;

  if (!res.ok) {
    throw new ApiError(res.status, describe(data, res.status));
  }
  return data as T;
}

function describe(data: unknown, status: number): string {
  if (data && typeof data === 'object' && 'detail' in data) {
    const detail = (data as { detail: unknown }).detail;
    if (typeof detail === 'string' && detail) return detail;
    if (Array.isArray(detail) && detail.length > 0) {
      const first = detail[0] as { msg?: string };
      if (typeof first?.msg === 'string') return first.msg;
    }
  }
  return `The server answered with an error (${status}).`;
}

// ------------------------------------------------------------------- auth

interface AuthResponse {
  token: string;
  user: { id: string; email: string; full_name: string | null };
}

export const auth = {
  async signIn(email: string, password: string): Promise<ApiUser> {
    const res = await apiFetch<AuthResponse>('/auth/login', {
      method: 'POST',
      body: { email, password },
    });
    const user = toApiUser(res.user);
    storeSession(res.token, user);
    return user;
  },

  async signUp(email: string, password: string, fullName?: string): Promise<ApiUser> {
    const res = await apiFetch<AuthResponse>('/auth/signup', {
      method: 'POST',
      body: { email, password, ...(fullName ? { full_name: fullName } : {}) },
    });
    const user = toApiUser(res.user);
    storeSession(res.token, user);
    return user;
  },

  signOut(): void {
    clearSession();
  },

  /** The cached user, refreshed from /auth/me when a token exists. */
  async me(): Promise<ApiUser | null> {
    if (!getToken()) return null;
    try {
      const raw = await apiFetch<{ id: string; email: string; full_name: string | null }>(
        '/auth/me',
      );
      const user = toApiUser(raw);
      localStorage.setItem(USER_KEY, JSON.stringify(user));
      return user;
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) return null;
      // Network hiccup: fall back to the cached copy so the shell still renders.
      try {
        const cached = localStorage.getItem(USER_KEY);
        if (cached) return JSON.parse(cached) as ApiUser;
      } catch {
        // fall through
      }
      throw e;
    }
  },

  async changePassword(currentPassword: string, newPassword: string): Promise<void> {
    await apiFetch('/auth/change-password', {
      method: 'POST',
      body: { current_password: currentPassword, new_password: newPassword },
    });
  },
};

/** The signed-in user's id, for the few spots that key caches by user. */
export async function currentUserId(): Promise<string> {
  const user = await auth.me();
  if (!user) throw new Error('You are signed out. Sign in again.');
  return user.id;
}
