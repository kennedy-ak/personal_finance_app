'use client';

import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui';
import { APP_NAME } from '@/components/logo';

/** The cookie the proxy reads; the web twin of SharedPreferences `seen_splash`. */
const SEEN_SPLASH = 'seen_splash';

/** Port of onboarding/presentation/splash_screen.dart. */
export default function WelcomePage() {
  const router = useRouter();

  function leave(to: '/signup' | '/login') {
    document.cookie = `${SEEN_SPLASH}=1; path=/; max-age=${60 * 60 * 24 * 365 * 5}; samesite=lax`;
    router.push(to);
  }

  return (
    <div className="motion-safe:animate-[rise_620ms_ease-out]">
      <h1 className="text-3xl font-semibold tracking-tight">Know what you can spend.</h1>
      <p className="mt-3 text-ink-muted">
        {APP_NAME} reads your accounts, your bills and your payday, then gives you one number.
      </p>
      <div className="mt-10 space-y-3">
        <Button className="h-12 w-full" onClick={() => leave('/signup')}>
          Get started
        </Button>
        <Button variant="secondary" className="h-12 w-full" onClick={() => leave('/login')}>
          I have an account
        </Button>
      </div>
    </div>
  );
}
