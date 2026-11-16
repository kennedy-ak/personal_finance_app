'use client';

import { useEffect } from 'react';
import { Loading } from '@/components/ui';
import { getToken } from '@/lib/api/client';

/**
 * Kept only so old confirmation links do not 404. The FastAPI backend has no
 * email confirmation — accounts work immediately — so this just sends the
 * visitor to the right place.
 */
export default function AuthCallbackPage() {
  useEffect(() => {
    window.location.replace(getToken() ? '/' : '/login');
  }, []);

  return (
    <main className="flex min-h-screen items-center justify-center px-4">
      <Loading label="One moment…" />
    </main>
  );
}
