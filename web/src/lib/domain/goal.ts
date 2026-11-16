/** Mirrors lib/features/planning/domain/goal.dart. */

import { diffDays, parseDate, today, type DateOnly } from '../dates';

export class Goal {
  constructor(
    readonly id: string,
    readonly userId: string,
    readonly name: string,
    readonly targetAmount: number,
    /** Set aside so far — the amount held back from spendable money. */
    readonly savedAmount: number,
    readonly targetDate: DateOnly | null,
    /** Where the money physically sits, if earmarked. */
    readonly accountId: string | null,
    /** Lower comes first. */
    readonly priority: number,
    readonly isActive: boolean,
    readonly createdAt: Date,
  ) {}

  get remaining(): number {
    const left = this.targetAmount - this.savedAmount;
    return left > 0 ? left : 0;
  }

  get progress(): number {
    if (this.targetAmount <= 0) return 0;
    return Math.min(1, Math.max(0, this.savedAmount / this.targetAmount));
  }

  get isComplete(): boolean {
    return this.savedAmount >= this.targetAmount;
  }

  /** Days left until the target date, or null if open-ended. */
  daysRemaining(now: DateOnly = today()): number | null {
    return this.targetDate === null ? null : diffDays(this.targetDate, now);
  }

  /** What must be set aside per month to land on time. */
  requiredMonthlyContribution(now: DateOnly = today()): number | null {
    const days = this.daysRemaining(now);
    if (days === null || this.isComplete) return null;
    const months = days / 30.44;
    if (months <= 0) return this.remaining;
    return this.remaining / months;
  }

  static fromRow(j: Record<string, unknown>): Goal {
    return new Goal(
      String(j.id),
      String(j.user_id),
      String(j.name),
      Number(j.target_amount),
      Number(j.saved_amount ?? 0),
      j.target_date ? parseDate(String(j.target_date)) : null,
      (j.account_id as string | null) ?? null,
      Number(j.priority ?? 0),
      j.is_active === undefined || j.is_active === null ? true : Boolean(j.is_active),
      new Date(String(j.created_at)),
    );
  }
}
