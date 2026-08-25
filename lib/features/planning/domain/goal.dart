/// Money the user has decided is not for spending.
///
/// A goal reserves part of the liquid pool. Without it, an emergency fund
/// sitting in a current account looks exactly like grocery money — which is
/// how emergency funds get spent.
class Goal {
  final String id;
  final String userId;
  final String name;
  final double targetAmount;

  /// How much has been set aside so far. This is the amount that gets held
  /// back from spendable money, not the target.
  final double savedAmount;

  final DateTime? targetDate;

  /// Where the money physically sits, if the user has earmarked an account.
  final String? accountId;

  /// Lower comes first when deciding what to protect.
  final int priority;

  final bool isActive;
  final DateTime createdAt;

  const Goal({
    required this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    required this.savedAmount,
    required this.targetDate,
    required this.accountId,
    required this.priority,
    required this.isActive,
    required this.createdAt,
  });

  double get remaining {
    final left = targetAmount - savedAmount;
    return left > 0 ? left : 0;
  }

  double get progress =>
      targetAmount <= 0 ? 0 : (savedAmount / targetAmount).clamp(0, 1).toDouble();

  bool get isComplete => savedAmount >= targetAmount;

  /// Days left until the target date, or null if the goal is open-ended.
  int? get daysRemaining {
    final t = targetDate;
    if (t == null) return null;
    final now = DateTime.now();
    return DateTime(t.year, t.month, t.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  /// What the user must set aside per month to land on time. Null when there is
  /// no deadline or the goal is already met.
  double? get requiredMonthlyContribution {
    final days = daysRemaining;
    if (days == null || isComplete) return null;
    final months = days / 30.44;
    if (months <= 0) return remaining;
    return remaining / months;
  }

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        name: j['name'] as String,
        targetAmount: (j['target_amount'] as num).toDouble(),
        savedAmount: (j['saved_amount'] as num?)?.toDouble() ?? 0,
        targetDate: j['target_date'] == null
            ? null
            : DateTime.parse(j['target_date'] as String),
        accountId: j['account_id'] as String?,
        priority: (j['priority'] as int?) ?? 0,
        isActive: (j['is_active'] as bool?) ?? true,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
