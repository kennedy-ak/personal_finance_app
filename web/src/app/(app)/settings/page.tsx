'use client';

import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import { useState, type ReactNode } from 'react';
import { signOut } from '@/components/app-shell';
import { Icon } from '@/components/icons';
import { ThemeSelect } from '@/components/theme-toggle';
import { Button, Card, Confirm, Glyph } from '@/components/ui';
import { useCategories, useGoals, useMe, useObligations } from '@/lib/data/hooks';
import { smsRepo } from '@/lib/data/sms';
import { displayName, hueFor, plural } from '@/lib/present';

/** Port of settings/presentation/settings_screen.dart. */
export default function SettingsPage() {
  const me = useMe();
  const obligations = useObligations();
  const goals = useGoals();
  const categories = useCategories();
  const smsCount = useQuery({ queryKey: ['sms', 'count'], queryFn: smsRepo.reviewCount, retry: false });
  const [confirmOut, setConfirmOut] = useState(false);

  const name = displayName(me.data?.user_metadata?.full_name as string | undefined, me.data?.email);
  const bills = (obligations.data ?? []).filter((o) => o.isActive && o.isOutflow).length;
  const activeGoals = (goals.data ?? []).filter((g) => g.isActive).length;
  const activeCats = (categories.data ?? []).filter((c) => !c.isHidden).length;
  const toReview = smsCount.data ?? 0;

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>

      <Card className="flex items-center gap-4">
        <Glyph name={name ?? me.data?.email ?? '?'} hue={hueFor(me.data?.email ?? '')} size={48} />
        <div className="min-w-0">
          <div className="font-semibold">{name ?? 'Signed in'}</div>
          <div className="truncate text-sm text-ink-muted">{me.data?.email ?? '…'}</div>
        </div>
      </Card>

      <Group title="Your money">
        <Row
          href="/plan"
          title="Commitments & goals"
          value={bills + activeGoals === 0 ? 'None yet' : `${plural(bills, 'bill')} · ${plural(activeGoals, 'goal')}`}
        />
        <Row href="/categories" title="Categories" value={`${activeCats} active`} />
        <Row
          href="/sms-import"
          title="SMS import"
          value={toReview > 0 ? `${plural(toReview, 'message')} to review` : 'Read MoMo & bank alerts'}
          detail="Alerts become records without typing them"
        />
      </Group>

      <Group title="Appearance">
        <div className="px-4 py-3">
          <div className="mb-2 text-sm font-medium">Theme</div>
          <ThemeSelect />
        </div>
      </Group>

      <Group title="AI coach">
        <Row href="/ai-history" title="Older conversations" />
        <p className="px-4 py-3 text-xs text-ink-muted">
          The coach runs on the server (the FastAPI backend), so no API key is stored in this browser.
        </p>
      </Group>

      <Group title="Reminders">
        <p className="px-4 py-3 text-sm text-ink-muted">
          Daily logging reminders and the morning tip notification are set in the phone app. The tip itself shows on
          Insights here every day.
        </p>
      </Group>

      <Group title="Security">
        <Row href="/auth/update-password" title="Change password" detail="Works for the app too" />
      </Group>

      <Button variant="danger" className="h-12 w-full" onClick={() => setConfirmOut(true)}>
        <Icon name="logout" width={16} height={16} /> Sign out
      </Button>

      <Confirm
        open={confirmOut}
        title="Sign out?"
        body="Your data stays on the server. You will need your password to get back in."
        confirmLabel="Sign out"
        cancelLabel="Stay"
        danger
        onClose={() => setConfirmOut(false)}
        onConfirm={signOut}
      />
    </div>
  );
}

function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 px-1 font-mono text-[11px] uppercase tracking-wider text-ink-faint">{title}</h2>
      <div className="divide-y divide-rule rounded-2xl border border-hairline bg-card">{children}</div>
    </section>
  );
}

function Row({ href, title, value, detail }: { href: string; title: string; value?: string; detail?: string }) {
  return (
    <Link href={href} className="flex items-center gap-3 px-4 py-3 hover:bg-recessed">
      <span className="flex-1">
        <span className="block text-sm font-medium">{title}</span>
        {detail && <span className="text-xs text-ink-muted">{detail}</span>}
      </span>
      {value && <span className="text-sm text-ink-muted">{value}</span>}
      <Icon name="arrowRight" width={16} height={16} className="text-ink-faint" />
    </Link>
  );
}
