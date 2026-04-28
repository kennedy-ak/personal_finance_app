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
  'Other',
];

const String kTransferCategory = 'Transfer';

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
