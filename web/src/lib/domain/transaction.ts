/** Mirrors lib/features/transactions/domain/transaction.dart. */

import { TRANSFER_CATEGORY } from '../constants';
import { parseDate, type DateOnly } from '../dates';

/** Stored verbatim in transactions.type. */
export type TxnType = 'Income' | 'Expense' | 'Transfer';

export class Txn {
  constructor(
    readonly id: string,
    readonly userId: string,
    /** Source account. For a transfer, the account money leaves. */
    readonly accountId: string,
    /** Destination account. Set only on transfers. */
    readonly toAccountId: string | null,
    readonly type: TxnType,
    readonly amount: number,
    readonly category: string,
    readonly description: string | null,
    readonly date: DateOnly,
    readonly createdAt: Date,
    /** 'manual' or 'sms'. */
    readonly source: string = 'manual',
    readonly externalRef: string | null = null,
  ) {}

  get cameFromSms(): boolean {
    return this.source === 'sms';
  }

  /**
   * Real money entering or leaving the user's control, as opposed to shuffling
   * it between their own accounts. Also catches the legacy shape, where a
   * transfer was faked as an Expense + Income pair tagged 'Transfer'.
   */
  get isRealMoneyMovement(): boolean {
    return this.type !== 'Transfer' && this.category !== TRANSFER_CATEGORY;
  }

  get isSpending(): boolean {
    return this.type === 'Expense' && this.isRealMoneyMovement;
  }

  get isIncome(): boolean {
    return this.type === 'Income' && this.isRealMoneyMovement;
  }

  /** Signed effect on a specific account's balance. */
  effectOn(accountId: string): number {
    if (this.type === 'Transfer') {
      if (this.accountId === accountId) return -this.amount;
      if (this.toAccountId === accountId) return this.amount;
      return 0;
    }
    if (this.accountId !== accountId) return 0;
    return this.type === 'Income' ? this.amount : -this.amount;
  }

  static fromRow(j: Record<string, unknown>): Txn {
    const t = String(j.type);
    return new Txn(
      String(j.id),
      String(j.user_id),
      String(j.account_id),
      (j.to_account_id as string | null) ?? null,
      t === 'Income' || t === 'Transfer' ? t : 'Expense',
      Number(j.amount),
      String(j.category),
      (j.description as string | null) ?? null,
      parseDate(String(j.date)),
      new Date(String(j.created_at)),
      (j.source as string | null) ?? 'manual',
      (j.external_ref as string | null) ?? null,
    );
  }
}
