'use client';

import Link from 'next/link';
import { useState, useSyncExternalStore, type FormEvent } from 'react';
import { Button, ErrorNote, Field, Input } from '@/components/ui';
import { auth, getToken } from '@/lib/api/client';

const noSubscribe = () => () => {};

/**
 * Change the signed-in user's password — POST /auth/change-password. The old
 * email-recovery flow is gone with Supabase; proving the current password
 * replaces proving control of the inbox.
 */
export default function UpdatePasswordPage() {
  const [done, setDone] = useState(false);
  const [current, setCurrent] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // True while prerendering, so the server and first client render agree;
  // useSyncExternalStore re-renders with the real answer on hydration.
  const hasToken = useSyncExternalStore(noSubscribe, () => Boolean(getToken()), () => true);
  const state: 'ready' | 'signed-out' | 'done' = done ? 'done' : hasToken ? 'ready' : 'signed-out';

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (password.length < 6) return setError('Use at least 6 characters.');
    if (password !== confirm) return setError('The two passwords do not match.');
    setBusy(true);
    setError(null);
    try {
      await auth.changePassword(current, password);
      setDone(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center px-4 py-12">
      <div className="w-full max-w-sm">
        <h1 className="text-2xl font-semibold tracking-tight">Choose a new password</h1>

        {state === 'signed-out' && (
          <div className="mt-4 space-y-4 text-sm text-ink-muted">
            <p>Sign in first — changing your password proves who you are with the current one.</p>
            <Link href="/login" className="font-medium text-brand-ink hover:underline">
              Go to sign in
            </Link>
          </div>
        )}

        {state === 'ready' && (
          <form onSubmit={submit} className="mt-8 space-y-4">
            <Field label="Current password">
              <Input
                type="password"
                autoComplete="current-password"
                required
                value={current}
                onChange={(e) => setCurrent(e.target.value)}
              />
            </Field>
            <Field label="New password">
              <Input
                type="password"
                autoComplete="new-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </Field>
            <Field label="Confirm new password">
              <Input
                type="password"
                autoComplete="new-password"
                required
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
              />
            </Field>
            <ErrorNote error={error} />
            <Button type="submit" busy={busy} className="w-full">
              Update password
            </Button>
          </form>
        )}

        {state === 'done' && (
          <div className="mt-4 space-y-4 text-sm text-ink-muted">
            <p>Password updated. It works in the app too.</p>
            <Link
              href="/"
              className="inline-flex h-10 items-center rounded-xl bg-brand px-4 text-sm font-medium text-on-brand hover:bg-brand-pressed"
            >
              Go to dashboard
            </Link>
          </div>
        )}
      </div>
    </main>
  );
}
