/** Mirrors lib/features/categories/domain/category.dart. */

import type { TxnType } from './transaction';

export type CategoryKind = 'expense' | 'income';

export const kindForTxn = (t: TxnType): CategoryKind =>
  t === 'Income' ? 'income' : 'expense';

export interface Category {
  id: string;
  name: string;
  kind: CategoryKind;
  /** Slug key, shared with the Flutter app's icon table. */
  icon: string | null;
  isHidden: boolean;
  isBuiltin: boolean;
  sortOrder: number;
}

export function categoryFromRow(j: Record<string, unknown>): Category {
  return {
    id: String(j.id),
    name: String(j.name),
    kind: j.kind === 'income' ? 'income' : 'expense',
    icon: (j.icon as string | null) ?? null,
    isHidden: Boolean(j.is_hidden ?? false),
    isBuiltin: Boolean(j.is_builtin ?? false),
    sortOrder: Number(j.sort_order ?? 0),
  };
}
