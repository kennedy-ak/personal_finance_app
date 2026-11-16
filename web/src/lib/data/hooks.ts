'use client';

/**
 * React Query hooks — the web twin of the Riverpod providers. Every screen and
 * the coach read the same cached lists, so they can never disagree.
 */

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useMemo, useSyncExternalStore } from 'react';
import { toIsoDate, today } from '../dates';
import { auth } from '../api/client';
import { EXPENSE_CATEGORIES, INCOME_CATEGORIES } from '../constants';
import { type CategoryKind } from '../domain/category';
import { buildAlerts } from '../finance/alerts';
import { buildSnapshot } from '../finance/money-engine';
import {
  accountsRepo,
  categoriesRepo,
  goalsRepo,
  obligationsRepo,
  transactionsRepo,
} from './repositories';

export const keys = {
  accounts: ['accounts'] as const,
  transactions: ['transactions'] as const,
  obligations: ['obligations'] as const,
  goals: ['goals'] as const,
  categories: ['categories'] as const,
};

/** The signed-in user, for greetings and the settings profile. */
export const useMe = () =>
  useQuery({
    queryKey: ['me'],
    queryFn: () => auth.me(),
    staleTime: Infinity,
  });

export const useAccounts = () => useQuery({ queryKey: keys.accounts, queryFn: accountsRepo.list });

export const useTransactions = () =>
  useQuery({ queryKey: keys.transactions, queryFn: transactionsRepo.list });

export const useObligations = () =>
  useQuery({ queryKey: keys.obligations, queryFn: obligationsRepo.list });

export const useGoals = () => useQuery({ queryKey: keys.goals, queryFn: goalsRepo.list });

export const useCategories = () =>
  useQuery({ queryKey: keys.categories, queryFn: categoriesRepo.list, retry: false });

/** Names the pickers offer: nothing hidden, the user's own order. */
export function useCategoryNames(kind: CategoryKind): string[] {
  const { data } = useCategories();
  const fallback = kind === 'income' ? INCOME_CATEGORIES : EXPENSE_CATEGORIES;
  const ofKind = (data ?? []).filter((c) => c.kind === kind);
  // Fall back only when there is nothing at all — someone who hid every
  // category gets an empty picker rather than the list resurrected.
  if (ofKind.length === 0) return fallback;
  return ofKind.filter((c) => !c.isHidden).map((c) => c.name);
}

/**
 * Everything the money engine needs, loaded together. `snapshot` and `alerts`
 * are undefined until all four lists have arrived.
 */
export function useMoney() {
  const accounts = useAccounts();
  const txns = useTransactions();
  const obligations = useObligations();
  const goals = useGoals();

  const all = [accounts, txns, obligations, goals];
  const error = all.find((q) => q.error)?.error ?? null;

  // Recompute only when one of the lists actually changes.
  const computed = useMemo(() => {
    if (!accounts.data || !txns.data || !obligations.data || !goals.data) return null;
    const snapshot = buildSnapshot({
      accounts: accounts.data,
      txns: txns.data,
      obligations: obligations.data,
      goals: goals.data,
    });
    const alerts = buildAlerts({ snapshot, obligations: obligations.data, goals: goals.data });
    return { snapshot, alerts };
  }, [accounts.data, txns.data, obligations.data, goals.data]);

  if (computed === null) {
    return { ready: false as const, isLoading: all.some((q) => q.isLoading), error };
  }
  const { snapshot, alerts } = computed;

  return {
    ready: true as const,
    isLoading: false,
    error,
    accounts: accounts.data!,
    txns: txns.data!,
    obligations: obligations.data!,
    goals: goals.data!,
    snapshot,
    alerts,
  };
}

/**
 * A write followed by a refresh of whatever it touched. A transaction changes
 * account balances (via the trigger), so it invalidates both.
 */
export function useWrite<TArgs>(
  fn: (args: TArgs) => Promise<void>,
  invalidates: readonly (readonly string[])[],
) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () =>
      Promise.all(invalidates.map((k) => qc.invalidateQueries({ queryKey: k }))),
  });
}

export const MONEY_KEYS = [keys.accounts, keys.transactions] as const;

const noSubscribe = () => () => {};

/**
 * Today as YYYY-MM-DD in the viewer's zone, or '' while prerendering — the
 * server's clock and zone must never be baked into the page.
 */
export function useTodayIso(): string {
  return useSyncExternalStore(noSubscribe, () => toIsoDate(today()), () => '');
}
