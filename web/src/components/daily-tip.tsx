'use client';

import { useQuery } from '@tanstack/react-query';
import { cachedBatch, generateBatch, tipForToday } from '@/lib/coach/tips';
import { useMoney } from '@/lib/data/hooks';
import { currentUserId } from '@/lib/api/client';
import { Eyebrow } from './ui';

/**
 * Port of insights/presentation/daily_tip_card.dart. A five-tip batch is
 * cached per user and one shown per day; it comes through the coach Edge
 * Function rather than a key in the browser.
 */
export function DailyTip() {
  const money = useMoney();
  const { data: tip, isLoading, isError } = useQuery({
    queryKey: ['daily-tip'],
    enabled: money.ready,
    staleTime: Infinity,
    retry: false,
    queryFn: async () => {
      if (!money.ready) return null;
      const userId = await currentUserId();
      const cached = cachedBatch(userId);
      const fromCache = cached && tipForToday(cached);
      if (fromCache) return fromCache;
      return tipForToday(await generateBatch({ userId, ...money }));
    },
  });

  return (
    <div className="rounded-2xl border border-accent-border bg-accent-surface px-4 py-3 text-accent">
      <Eyebrow className="text-current opacity-80">Today</Eyebrow>
      <p className="mt-1 text-sm">
        {isLoading || !money.ready
          ? 'Reading your position…'
          : isError || !tip
            ? 'No tip today — the coach could not be reached. Nothing was charged and your numbers are unchanged.'
            : tip}
      </p>
    </div>
  );
}
