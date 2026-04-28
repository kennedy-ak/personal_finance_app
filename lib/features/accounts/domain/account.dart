class Account {
  final String id;
  final String userId;
  final String name;
  final double balance;
  final DateTime createdAt;

  const Account({
    required this.id,
    required this.userId,
    required this.name,
    required this.balance,
    required this.createdAt,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        name: j['name'] as String,
        balance: (j['balance'] as num).toDouble(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
