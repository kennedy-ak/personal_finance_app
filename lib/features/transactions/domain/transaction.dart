enum TxnType {
  income('Income'),
  expense('Expense');

  final String label;
  const TxnType(this.label);

  static TxnType fromLabel(String s) =>
      values.firstWhere((t) => t.label == s, orElse: () => TxnType.expense);
}

class Txn {
  final String id;
  final String userId;
  final String accountId;
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
    required this.type,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
    required this.createdAt,
  });

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        accountId: j['account_id'] as String,
        type: TxnType.fromLabel(j['type'] as String),
        amount: (j['amount'] as num).toDouble(),
        category: j['category'] as String,
        description: j['description'] as String?,
        date: DateTime.parse(j['date'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
