'use client';

import Link from 'next/link';

/**
 * The FastAPI backend sends no email, so there is no reset link to send.
 * Passwords change from Settings while signed in (/auth/update-password).
 */
export default function ForgotPasswordPage() {
  return (
    <>
      <h1 className="text-2xl font-semibold tracking-tight">Reset your password</h1>
      <div className="mt-4 space-y-4 text-sm text-ink-muted">
        <p>
          Password reset by email is not available on this server. If you are signed in on another
          device — this browser, or the phone app — change your password from Settings there, and it
          works everywhere.
        </p>
        <p>If you are locked out entirely, ask whoever runs the backend to reset your account.</p>
      </div>
      <Link href="/login" className="mt-6 inline-block text-sm text-ink-muted hover:text-ink">
        Back to sign in
      </Link>
    </>
  );
}
