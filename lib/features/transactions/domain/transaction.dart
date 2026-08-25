import '../../../core/constants.dart';

enum TxnType {
  income('Income'),
  expense('Expense'),

  /// Money moved between the user's own accounts. Never income, never
  /// spending — it changes where money sits, not how much there is.
  transfer('Transfer');

  final String label;
  const TxnType(this.label);

  static TxnType fromLabel(String s) =>
      values.firstWhere((t) => t.label == s, orElse: () => TxnType.expense);
}

class Txn {
  final String id;
  final String userId;

  /// Source account. For a transfer this is the account money leaves.
  final String accountId;

  /// Destination account. Set only on transfers.
  final String? toAccountId;

  final TxnType type;
  final double amount;
  final String category;
  final String? description;
  final DateTime date;
  final DateTime createdAt;

  const Txn({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.toAccountId,
    required this.type,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
    required this.createdAt,
  });

  /// Whether this row represents real money entering or leaving the user's
  /// control, as opposed to shuffling it between their own accounts.
  ///
  /// This is the single guard that keeps transfers out of income, expense,
  /// category totals and burn rate. It also catches the legacy shape, where a
  /// transfer was faked as an Expense + Income pair tagged 'Transfer'.
  bool get isRealMoneyMovement =>
      type != TxnType.transfer && category != kTransferCategory;

  bool get isSpending => type == TxnType.expense && isRealMoneyMovement;
  bool get isIncome => type == TxnType.income && isRealMoneyMovement;

  /// Signed effect on a specific account's balance.
  double effectOn(String accountId) {
    if (type == TxnType.transfer) {
      if (this.accountId == accountId) return -amount;
      if (toAccountId == accountId) return amount;
      return 0;
    }
    if (this.accountId != accountId) return 0;
    return type == TxnType.income ? amount : -amount;
  }

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        accountId: j['account_id'] as String,
        toAccountId: j['to_account_id'] as String?,
        type: TxnType.fromLabel(j['type'] as String),
        amount: (j['amount'] as num).toDouble(),
        category: j['category'] as String,
        description: j['description'] as String?,
        date: DateTime.parse(j['date'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
