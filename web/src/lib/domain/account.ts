/** Mirrors lib/features/accounts/domain/account.dart. */

export type AccountKind = 'bank' | 'momo' | 'cash' | 'savings' | 'investment' | 'credit';

export const ACCOUNT_KINDS: { value: AccountKind; label: string }[] = [
  { value: 'bank', label: 'Bank' },
  { value: 'momo', label: 'Mobile Money' },
  { value: 'cash', label: 'Cash' },
  { value: 'savings', label: 'Savings' },
  { value: 'investment', label: 'Investment' },
  { value: 'credit', label: 'Credit' },
];

/** How freely this money can be spent. */
export type Liquidity = 'liquid' | 'reserved' | 'locked';

export const LIQUIDITIES: { value: Liquidity; label: string; hint: string }[] = [
  { value: 'liquid', label: 'Spendable', hint: 'Spend it today without consequence.' },
  { value: 'reserved', label: 'Reserved', hint: 'There, but meant for something.' },
  { value: 'locked', label: 'Locked', hint: 'Fixed deposit, investment, long-term savings.' },
];

export const kindLabel = (k: AccountKind) =>
  ACCOUNT_KINDS.find((x) => x.value === k)?.label ?? 'Bank';

export const liquidityLabel = (l: Liquidity) =>
  LIQUIDITIES.find((x) => x.value === l)?.label ?? 'Spendable';

const KIND_VALUES = ACCOUNT_KINDS.map((k) => k.value);
const LIQUIDITY_VALUES = LIQUIDITIES.map((l) => l.value);

export class Account {
  constructor(
    readonly id: string,
    readonly userId: string,
    readonly name: string,
    readonly balance: number,
    readonly kind: AccountKind,
    readonly liquidity: Liquidity,
    /** Floor this account should not drop below. */
    readonly minBalance: number,
    /** What the user says this account is for. Fed to the coach. */
    readonly purpose: string | null,
    /** Balance that predates the transaction history. */
    readonly openingBalance: number,
    readonly isArchived: boolean,
    readonly sortOrder: number,
    readonly createdAt: Date,
  ) {}

  /** What could come out right now without breaking the floor. Never negative. */
  get available(): number {
    const free = this.balance - this.minBalance;
    return free > 0 ? free : 0;
  }

  get isSpendable(): boolean {
    return !this.isArchived && this.liquidity === 'liquid';
  }

  get isBelowFloor(): boolean {
    return this.minBalance > 0 && this.balance < this.minBalance;
  }

  static fromRow(j: Record<string, unknown>): Account {
    const kind = String(j.kind ?? 'bank') as AccountKind;
    const liq = String(j.liquidity ?? 'liquid') as Liquidity;
    return new Account(
      String(j.id),
      String(j.user_id),
      String(j.name),
      Number(j.balance ?? 0),
      KIND_VALUES.includes(kind) ? kind : 'bank',
      LIQUIDITY_VALUES.includes(liq) ? liq : 'liquid',
      Number(j.min_balance ?? 0),
      (j.purpose as string | null) ?? null,
      Number(j.opening_balance ?? 0),
      Boolean(j.is_archived ?? false),
      Number(j.sort_order ?? 0),
      new Date(String(j.created_at)),
    );
  }
}
