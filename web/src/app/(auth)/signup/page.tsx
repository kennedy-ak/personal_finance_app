'use client';

import Link from 'next/link';
import { useState, type FormEvent } from 'react';
import { Button, Field, Input, PasswordInput } from '@/components/ui';
import { auth } from '@/lib/api/client';

/** Port of auth/presentation/signup_screen.dart — same fields and rules. */
export default function SignupPage() {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<{ name?: string; email?: string; password?: string }>({});

  async function submit(e: FormEvent) {
    e.preventDefault();
    const errs: typeof fieldErrors = {};
    if (!name.trim()) errs.name = 'Tell us what to call you';
    if (!email.includes('@')) errs.email = 'Enter a valid email';
    if (password.length < 8) errs.password = 'At least 8 characters';
    setFieldErrors(errs);
    if (Object.keys(errs).length) return;

    setBusy(true);
    setError(null);
    try {
      await auth.signUp(email.trim(), password, name.trim());
    } catch (err) {
      setBusy(false);
      setError(err instanceof Error ? err.message : String(err));
      return;
    }
    setBusy(false);
    // Full load so the proxy sees the new session cookie. No email
    // confirmation exists on this backend — the account works immediately.
    // eslint-disable-next-line @next/next/no-location-assign-relative-destination
    window.location.assign('/');
  }

  return (
    <>
      <h1 className="text-2xl font-semibold tracking-tight">Set up your money</h1>
      <p className="mt-1 text-sm text-ink-muted">Three fields. You add accounts next.</p>

      <form onSubmit={submit} noValidate className="mt-8 space-y-4">
          <Field label="Name" error={fieldErrors.name}>
            <Input autoComplete="name" placeholder="Ama Mensah" value={name} onChange={(e) => setName(e.target.value)} />
          </Field>
          <Field label="Email" error={fieldErrors.email}>
            <Input
              type="email"
              autoComplete="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </Field>
          <Field label="Password" error={fieldErrors.password}>
            <PasswordInput
              autoComplete="new-password"
              placeholder="At least 8 characters"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </Field>
          {error && (
            <div role="alert" className="rounded-xl border border-expense-border bg-expense-surface px-4 py-3 text-sm text-expense">
              <div className="font-medium">Could not create account</div>
              <div className="mt-0.5">{error}</div>
            </div>
          )}
          <Button type="submit" busy={busy} className="w-full">
            Create account
          </Button>
          <p className="text-center text-xs text-ink-faint">
            By continuing you agree to the terms and privacy notice.
          </p>
        </form>

      <p className="mt-6 text-center text-sm text-ink-muted">
        Already have one?{' '}
        <Link href="/login" className="font-medium text-brand-ink hover:underline">
          Log in
        </Link>
      </p>
    </>
  );
}
