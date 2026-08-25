/// The starting list, kept as a constant for two jobs only: seeding a new
/// user's categories (see migration 0007) and standing in when the real list
/// has not loaded. Everything the user sees comes from the categories table —
/// edit those in the app, not here.
const List<String> kExpenseCategories = [
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

const String kTransferCategory = 'Transfer';

/// Where the fees banks levy on a transaction land.
///
/// Kept out of the merchant's own row: MTN charges GHS 2.64 on a GHS 264
/// payment, and folding that in would overstate every merchant total while
/// leaving the balance quietly adrift.
const String kBankChargesCategory = 'Bank Charges';

const List<String> kIncomeCategories = [
  'Salary',
  'Business',
  'Investment',
  'Gift',
  'Refund',
  'Other',
];

class QuickAdd {
  final String label;
  final String category;
  final double amount;
  const QuickAdd(this.label, this.category, this.amount);
}

const List<QuickAdd> kQuickAdds = [
  QuickAdd('Coffee', 'Food & Dining', 5),
  QuickAdd('Lunch', 'Food & Dining', 15),
  QuickAdd('Gas', 'Transportation', 50),
  QuickAdd('Groceries', 'Shopping', 100),
];
