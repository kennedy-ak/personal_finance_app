'use client';

import Link from 'next/link';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Field, Input, PasswordInput } from '@/components/ui';
import { auth } from '@/lib/api/client';

/** Same key name as the app's SharedPreferences `last_email`. */
const LAST_EMAIL = 'last_email';

export default function LoginPage() {
  const emailRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<{ email?: string; password?: string }>({});
  const [notice, setNotice] = useState<string | null>(null);

  // Remember who signed in last on this device. Written straight into the
  // (uncontrolled) field so server and client render the same HTML.
  useEffect(() => {
    try {
      const last = localStorage.getItem(LAST_EMAIL);
      if (last && emailRef.current && !emailRef.current.value) emailRef.current.value = last;
    } catch {}
  }, []);

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const email = String(form.get('email') ?? '').trim();
    const password = String(form.get('password') ?? '');

    const errs: typeof fieldErrors = {};
    if (!email.includes('@')) errs.email = 'Enter a valid email';
    if (password.length < 6) errs.password = 'Min 6 characters';
    setFieldErrors(errs);
    if (Object.keys(errs).length) return;

    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      await auth.signIn(email, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setBusy(false);
      return;
    }
    try {
      localStorage.setItem(LAST_EMAIL, email);
    } catch {}
    // A full load on purpose: the proxy sees the new cookie, and nothing cached
    // in memory for a previous user survives.
    // eslint-disable-next-line @next/next/no-location-assign-relative-destination
    window.location.assign('/');
  }

  function forgot() {
    setNotice(null);
    // The backend sends no email — say so instead of pretending.
    setError(
      'Password reset by email is not available. If you are signed in on ' +
        'another device, change your password from Settings there.',
    );
  }

  return (
    <>
      <h1 className="text-2xl font-semibold tracking-tight">Welcome back</h1>
      <p className="mt-1 text-sm text-ink-muted">Same account as the app on your phone.</p>

      <form onSubmit={submit} noValidate className="mt-8 space-y-4">
        <Field label="Email" error={fieldErrors.email}>
          <Input ref={emailRef} name="email" type="email" autoComplete="email" placeholder="you@example.com" />
        </Field>
        <Field label="Password" error={fieldErrors.password}>
          <PasswordInput name="password" autoComplete="current-password" invalid={Boolean(error)} />
        </Field>

        {error && (
          <div role="alert" className="rounded-xl border border-expense-border bg-expense-surface px-4 py-3 text-sm text-expense">
            <div className="font-medium">Could not sign in</div>
            <div className="mt-0.5">{error}</div>
          </div>
        )}
        {notice && (
          <div role="status" className="rounded-xl border border-info-border bg-info-surface px-4 py-3 text-sm text-info">
            <div className="font-medium">Check your email</div>
            <div className="mt-0.5">{notice}</div>
          </div>
        )}

        <Button type="submit" busy={busy} className="w-full">
          Log in
        </Button>
      </form>

      <div className="mt-6 flex flex-col items-center gap-3 text-sm">
        <button type="button" onClick={forgot} className="text-ink-muted hover:text-ink">
          Forgot password
        </button>
        <p className="text-ink-muted">
          New here?{' '}
          <Link href="/signup" className="font-medium text-brand-ink hover:underline">
            Create an account
          </Link>
        </p>
        <Link href="/welcome" className="text-xs text-ink-faint hover:text-ink">
          ← Back
        </Link>
      </div>
    </>
  );
}
