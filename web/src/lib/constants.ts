/**
 * Mirrors lib/core/constants.dart. The starting list is only a fallback for
 * when the categories table has not loaded; everything the user sees comes
 * from that table.
 */

export const EXPENSE_CATEGORIES = [
  'Food & Dining',
  'Transportation',
  'Shopping',
  'Entertainment',
  'Bills & Utilities',
  'Healthcare',
  'Education',
  'Travel',
  'Housing',
  'Insurance',
  'Gifts & Donations',
  'Bank Charges',
  'Other',
];

export const TRANSFER_CATEGORY = 'Transfer';

export const BANK_CHARGES_CATEGORY = 'Bank Charges';

export const INCOME_CATEGORIES = [
  'Salary',
  'Business',
  'Investment',
  'Gift',
  'Refund',
  'Other',
];

export interface QuickAdd {
  label: string;
  category: string;
  amount: number;
}

export const QUICK_ADDS: QuickAdd[] = [
  { label: 'Coffee', category: 'Food & Dining', amount: 5 },
  { label: 'Lunch', category: 'Food & Dining', amount: 15 },
  { label: 'Gas', category: 'Transportation', amount: 50 },
  { label: 'Groceries', category: 'Shopping', amount: 100 },
];
