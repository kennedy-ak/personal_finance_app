'use client';

/**
 * Backend reads and writes, one block per table — the web twin of the Dart
 * repositories under lib/features/x/data/. The FastAPI backend scopes every
 * query to the bearer token's user, so no user_id rides along.
 *
 * Balances are never written directly: the backend recomputes them from
 * opening_balance plus transactions after every write.
 */

import { TRANSFER_CATEGORY } from '../constants';
import { apiFetch } from '../api/client';
import { toIsoDate, type DateOnly } from '../dates';
import { Account, type AccountKind, type Liquidity } from '../domain/account';
import { categoryFromRow, type Category, type CategoryKind } from '../domain/category';
import { Goal } from '../domain/goal';
import { Obligation, type Cadence, type ObligationDirection } from '../domain/obligation';
import { Txn, type TxnType } from '../domain/transaction';

type Row = Record<string, unknown>;

// --- Accounts ---------------------------------------------------------------

export const accountsRepo = {
  async list(): Promise<Account[]> {
    const rows = await apiFetch<Row[]>('/accounts');
    return rows.map(Account.fromRow);
  },

  async create(a: {
    name: string;
    openingBalance: number;
    kind: AccountKind;
    liquidity: Liquidity;
    minBalance: number;
    purpose: string | null;
    sortOrder?: number;
  }): Promise<void> {
    await apiFetch('/accounts', {
      method: 'POST',
      body: {
        name: a.name,
        opening_balance: a.openingBalance,
        kind: a.kind,
        liquidity: a.liquidity,
        min_balance: a.minBalance,
        purpose: a.purpose || null,
        sort_order: a.sortOrder ?? 0,
      },
    });
  },

  async update(
    id: string,
    patch: Partial<{
      name: string;
      kind: AccountKind;
      liquidity: Liquidity;
      minBalance: number;
      purpose: string | null;
      isArchived: boolean;
      sortOrder: number;
    }>,
  ): Promise<void> {
    const row: Row = {};
    if (patch.name !== undefined) row.name = patch.name;
    if (patch.kind !== undefined) row.kind = patch.kind;
    if (patch.liquidity !== undefined) row.liquidity = patch.liquidity;
    if (patch.minBalance !== undefined) row.min_balance = patch.minBalance;
    if (patch.purpose !== undefined) row.purpose = patch.purpose || null;
    if (patch.isArchived !== undefined) row.is_archived = patch.isArchived;
    if (patch.sortOrder !== undefined) row.sort_order = patch.sortOrder;
    if (Object.keys(row).length === 0) return;
    await apiFetch(`/accounts/${id}`, { method: 'PATCH', body: row });
  },

  /**
   * Corrects the balance without inventing a transaction: shifts the opening
   * balance by the difference and lets the backend settle it.
   */
  async reconcileBalance(account: Account, newBalance: number): Promise<void> {
    const delta = newBalance - account.balance;
    if (Math.abs(delta) < 0.005) return;
    await apiFetch(`/accounts/${account.id}`, {
      method: 'PATCH',
      body: { opening_balance: account.openingBalance + delta },
    });
  },

  async remove(id: string): Promise<void> {
    await apiFetch(`/accounts/${id}`, { method: 'DELETE' });
  },
};

// --- Transactions -----------------------------------------------------------

export const transactionsRepo = {
  async list(): Promise<Txn[]> {
    const rows = await apiFetch<Row[]>('/transactions');
    return rows.map(Txn.fromRow);
  },

  async create(t: {
    accountId: string;
    type: Exclude<TxnType, 'Transfer'>;
    amount: number;
    category: string;
    description: string | null;
    date: DateOnly;
  }): Promise<void> {
    await apiFetch('/transactions', {
      method: 'POST',
      body: {
        account_id: t.accountId,
        type: t.type,
        amount: t.amount,
        category: t.category,
        description: t.description || null,
        date: toIsoDate(t.date),
      },
    });
  },

  /**
   * One row, not the old Expense + Income pair, so a movement between the
   * user's own accounts never lands in income or spending.
   */
  async createTransfer(t: {
    fromAccountId: string;
    toAccountId: string;
    amount: number;
    description: string | null;
    date: DateOnly;
  }): Promise<void> {
    if (t.fromAccountId === t.toAccountId) {
      throw new Error('A transfer needs two different accounts.');
    }
    await apiFetch('/transactions', {
      method: 'POST',
      body: {
        account_id: t.fromAccountId,
        to_account_id: t.toAccountId,
        type: 'Transfer',
        amount: t.amount,
        category: TRANSFER_CATEGORY,
        description: t.description || null,
        date: toIsoDate(t.date),
      },
    });
  },

  async remove(id: string): Promise<void> {
    await apiFetch(`/transactions/${id}`, { method: 'DELETE' });
  },
};

// --- Obligations ------------------------------------------------------------

export const obligationsRepo = {
  async list(): Promise<Obligation[]> {
    const rows = await apiFetch<Row[]>('/obligations');
    return rows.map(Obligation.fromRow);
  },

  async create(o: {
    name: string;
    amount: number;
    nextDue: DateOnly;
    direction: ObligationDirection;
    cadence: Cadence;
    accountId: string | null;
    category?: string | null;
  }): Promise<void> {
    await apiFetch('/obligations', {
      method: 'POST',
      body: {
        name: o.name,
        direction: o.direction,
        amount: o.amount,
        cadence: o.cadence,
        next_due: toIsoDate(o.nextDue),
        account_id: o.accountId,
        category: o.category ?? null,
      },
    });
  },

  async update(
    id: string,
    p: Partial<{
      name: string;
      amount: number;
      nextDue: DateOnly;
      direction: ObligationDirection;
      cadence: Cadence;
      accountId: string | null;
      category: string | null;
      isActive: boolean;
    }>,
  ): Promise<void> {
    const row: Row = {};
    if (p.name !== undefined) row.name = p.name;
    if (p.category !== undefined) row.category = p.category || null;
    if (p.amount !== undefined) row.amount = p.amount;
    if (p.nextDue !== undefined) row.next_due = toIsoDate(p.nextDue);
    if (p.direction !== undefined) row.direction = p.direction;
    if (p.cadence !== undefined) row.cadence = p.cadence;
    if (p.accountId !== undefined) row.account_id = p.accountId || null;
    if (p.isActive !== undefined) row.is_active = p.isActive;
    if (Object.keys(row).length === 0) return;
    await apiFetch(`/obligations/${id}`, { method: 'PATCH', body: row });
  },

  async remove(id: string): Promise<void> {
    await apiFetch(`/obligations/${id}`, { method: 'DELETE' });
  },
};

// --- Goals ------------------------------------------------------------------

export const goalsRepo = {
  async list(): Promise<Goal[]> {
    const rows = await apiFetch<Row[]>('/goals');
    return rows.map(Goal.fromRow);
  },

  async create(g: {
    name: string;
    targetAmount: number;
    savedAmount: number;
    targetDate: DateOnly | null;
    accountId: string | null;
    priority: number;
  }): Promise<void> {
    await apiFetch('/goals', {
      method: 'POST',
      body: {
        name: g.name,
        target_amount: g.targetAmount,
        saved_amount: g.savedAmount,
        target_date: g.targetDate ? toIsoDate(g.targetDate) : null,
        account_id: g.accountId,
        priority: g.priority,
      },
    });
  },

  async update(
    id: string,
    p: Partial<{
      name: string;
      targetAmount: number;
      savedAmount: number;
      targetDate: DateOnly | null;
      accountId: string | null;
      priority: number;
      isActive: boolean;
    }>,
  ): Promise<void> {
    const row: Row = {};
    if (p.name !== undefined) row.name = p.name;
    if (p.targetAmount !== undefined) row.target_amount = p.targetAmount;
    if (p.savedAmount !== undefined) row.saved_amount = p.savedAmount;
    if (p.targetDate !== undefined) row.target_date = p.targetDate ? toIsoDate(p.targetDate) : null;
    if (p.accountId !== undefined) row.account_id = p.accountId || null;
    if (p.priority !== undefined) row.priority = p.priority;
    if (p.isActive !== undefined) row.is_active = p.isActive;
    if (Object.keys(row).length === 0) return;
    await apiFetch(`/goals/${id}`, { method: 'PATCH', body: row });
  },

  /** Adds to (or takes from) what has been set aside, never below zero. */
  async contribute(goal: Goal, delta: number): Promise<void> {
    await goalsRepo.update(goal.id, { savedAmount: Math.max(0, goal.savedAmount + delta) });
  },

  async remove(id: string): Promise<void> {
    await apiFetch(`/goals/${id}`, { method: 'DELETE' });
  },
};

// --- Categories -------------------------------------------------------------

/**
 * With the FastAPI backend the categories table is created on boot, so this
 * never matches. Kept because the category screens still branch on it.
 */
export function isCategoriesTableMissing(e: unknown): boolean {
  void e;
  return false;
}

export const categoriesRepo = {
  async list(): Promise<Category[]> {
    const rows = await apiFetch<Row[]>('/categories');
    return rows.map(categoryFromRow);
  },

  async create(c: { name: string; kind: CategoryKind; icon?: string | null }): Promise<void> {
    await apiFetch('/categories', {
      method: 'POST',
      body: { name: c.name, kind: c.kind, icon: c.icon ?? null, sort_order: 100 },
    });
  },

  /** Renames the category *and* every transaction wearing the old label. */
  async rename(id: string, newName: string): Promise<void> {
    await apiFetch(`/categories/${id}/rename`, { method: 'POST', body: { new_name: newName } });
  },

  async setIcon(id: string, icon: string | null): Promise<void> {
    await apiFetch(`/categories/${id}`, { method: 'PATCH', body: { icon } });
  },

  async setHidden(id: string, hidden: boolean): Promise<void> {
    await apiFetch(`/categories/${id}`, { method: 'PATCH', body: { is_hidden: hidden } });
  },

  async usageCount(id: string): Promise<number> {
    const res = await apiFetch<{ count: number }>(`/categories/${id}/usage`);
    return Number(res.count ?? 0);
  },

  /** Transactions keep their label — the column is free text. */
  async remove(id: string): Promise<void> {
    await apiFetch(`/categories/${id}`, { method: 'DELETE' });
  },

  async restoreDefaults(): Promise<void> {
    await apiFetch('/categories/restore-defaults', { method: 'POST' });
  },
};
