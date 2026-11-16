'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { type ReactNode } from 'react';
import { auth } from '@/lib/api/client';
import { Icon, type IconName } from './icons';
import { Wordmark } from './logo';
import { ThemeToggle } from './theme-toggle';
import { cx } from './ui';

/** The five tabs of the Flutter shell, in the same order. */
const TABS: { href: string; label: string; icon: IconName }[] = [
  { href: '/', label: 'Home', icon: 'home' },
  { href: '/history', label: 'History', icon: 'history' },
  { href: '/reports', label: 'Reports', icon: 'reports' },
  { href: '/insights', label: 'Insights', icon: 'insights' },
  { href: '/accounts', label: 'Accounts', icon: 'accounts' },
];

const MORE: { href: string; label: string; icon: IconName }[] = [
  { href: '/plan', label: 'Commitments', icon: 'plan' },
  { href: '/pay', label: 'Pay someone', icon: 'pay' },
  { href: '/categories', label: 'Categories', icon: 'tag' },
  { href: '/sms-import', label: 'SMS import', icon: 'send' },
  { href: '/settings', label: 'Settings', icon: 'settings' },
];

function isActive(path: string, href: string) {
  return href === '/' ? path === '/' : path === href || path.startsWith(`${href}/`);
}

export async function signOut() {
  auth.signOut();
  // A full load on purpose: drops every cached query for the signed-out user.
  // eslint-disable-next-line @next/next/no-location-assign-relative-destination
  window.location.assign('/login');
}

export function AppShell({ children }: { children: ReactNode }) {
  const path = usePathname();

  return (
    <div className="min-h-screen lg:flex">
      {/* Desktop sidebar */}
      <aside className="sticky top-0 hidden h-screen w-60 shrink-0 flex-col border-r border-hairline bg-card px-3 py-5 lg:flex">
        <Link href="/" className="mb-6 flex px-2">
          <Wordmark size={32} />
        </Link>

        <Link
          href="/add"
          className="mb-5 flex h-10 items-center justify-center gap-2 rounded-xl bg-brand text-sm font-medium text-on-brand hover:bg-brand-pressed"
        >
          <Icon name="plus" width={18} height={18} /> Add transaction
        </Link>

        <nav aria-label="Main" className="space-y-0.5">
          {TABS.map((t) => (
            <NavLink key={t.href} {...t} active={isActive(path, t.href)} />
          ))}
        </nav>
        <div className="mx-2 my-4 border-t border-hairline" />
        <nav aria-label="More" className="space-y-0.5">
          {MORE.map((t) => (
            <NavLink key={t.href} {...t} active={isActive(path, t.href)} />
          ))}
        </nav>

        <div className="mt-auto flex items-center justify-between px-1">
          <button
            type="button"
            onClick={signOut}
            className="flex items-center gap-2 rounded-lg px-2 py-2 text-sm text-ink-muted hover:bg-recessed hover:text-ink"
          >
            <Icon name="logout" width={18} height={18} /> Sign out
          </button>
          <ThemeToggle />
        </div>
      </aside>

      {/* Mobile top bar */}
      <header className="sticky top-0 z-20 flex items-center justify-between border-b border-hairline bg-canvas/90 px-4 py-3 backdrop-blur lg:hidden">
        <Link href="/" className="flex">
          <Wordmark size={28} />
        </Link>
        <div className="flex items-center gap-1">
          <ThemeToggle />
          <Link
            href="/settings"
            aria-label="Settings"
            className="rounded-lg p-2 text-ink-muted hover:bg-recessed hover:text-ink"
          >
            <Icon name="settings" />
          </Link>
        </div>
      </header>

      <main className="mx-auto w-full max-w-5xl flex-1 px-4 pb-28 pt-6 sm:px-6 lg:px-10 lg:pb-12 lg:pt-10">
        {children}
      </main>

      {/* Mobile bottom tabs */}
      <nav
        aria-label="Main"
        className="fixed inset-x-0 bottom-0 z-20 grid grid-cols-5 border-t border-hairline bg-card pb-[env(safe-area-inset-bottom)] lg:hidden"
      >
        {TABS.map((t) => {
          const active = isActive(path, t.href);
          return (
            <Link
              key={t.href}
              href={t.href}
              aria-current={active ? 'page' : undefined}
              className={cx(
                'flex flex-col items-center gap-0.5 py-2 text-[11px]',
                active ? 'text-brand-ink' : 'text-ink-muted',
              )}
            >
              <Icon name={t.icon} />
              {t.label}
            </Link>
          );
        })}
      </nav>
      {/* Hidden on Insights, which has its own composer — as in home_shell.dart. */}
      {!isActive(path, '/insights') && (
        <Link
          href="/add"
          aria-label="Add transaction"
          className="fixed bottom-20 right-4 z-30 flex h-14 w-14 items-center justify-center rounded-2xl bg-brand text-on-brand shadow-lg lg:hidden"
        >
          <Icon name="plus" width={24} height={24} />
        </Link>
      )}
    </div>
  );
}

function NavLink({
  href,
  label,
  icon,
  active,
}: {
  href: string;
  label: string;
  icon: IconName;
  active: boolean;
}) {
  return (
    <Link
      href={href}
      aria-current={active ? 'page' : undefined}
      className={cx(
        'flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors',
        active
          ? 'bg-info-surface font-medium text-brand-ink'
          : 'text-ink-muted hover:bg-recessed hover:text-ink',
      )}
    >
      <Icon name={icon} width={18} height={18} />
      {label}
    </Link>
  );
}
