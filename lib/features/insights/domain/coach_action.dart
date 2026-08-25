import '../../planning/domain/obligation.dart';

/// Something the coach is offering to do, pending the user's tap.
///
/// Nothing in here has happened. An action is a proposal that gets rendered as
/// a card with an Apply button — the coach never moves money or writes records
/// on its own, no matter how confident it sounds.
sealed class CoachAction {
  const CoachAction();

  /// Discriminator used when the action is stored on a message row.
  String get type;

  Map<String, dynamic> toJson();

  static CoachAction? fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'transfer' => TransferAction.fromJson(j),
        'commitment' => CommitmentAction.fromJson(j),
        _ => null,
      };
}

/// Move money between two of the user's own accounts.
class TransferAction extends CoachAction {
  final String fromAccountId;
  final String fromAccountName;
  final String toAccountId;
  final String toAccountName;
  final double amount;
  final String reason;

  const TransferAction({
    required this.fromAccountId,
    required this.fromAccountName,
    required this.toAccountId,
    required this.toAccountName,
    required this.amount,
    required this.reason,
  });

  @override
  String get type => 'transfer';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'from_account_id': fromAccountId,
        'from_account_name': fromAccountName,
        'to_account_id': toAccountId,
        'to_account_name': toAccountName,
        'amount': amount,
        'reason': reason,
      };

  factory TransferAction.fromJson(Map<String, dynamic> j) => TransferAction(
        fromAccountId: j['from_account_id'] as String,
        fromAccountName: j['from_account_name'] as String,
        toAccountId: j['to_account_id'] as String,
        toAccountName: j['to_account_name'] as String,
        amount: (j['amount'] as num).toDouble(),
        reason: (j['reason'] as String?) ?? '',
      );
}

/// Record a recurring bill or expected income the user mentioned but never
/// logged.
class CommitmentAction extends CoachAction {
  final String name;
  final double amount;
  final ObligationDirection direction;
  final Cadence cadence;
  final DateTime nextDue;
  final String? accountId;
  final String? accountName;

  const CommitmentAction({
    required this.name,
    required this.amount,
    required this.direction,
    required this.cadence,
    required this.nextDue,
    required this.accountId,
    required this.accountName,
  });

  @override
  String get type => 'commitment';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'amount': amount,
        'direction': direction.value,
        'cadence': cadence.value,
        'next_due': nextDue.toIso8601String(),
        'account_id': accountId,
        'account_name': accountName,
      };

  factory CommitmentAction.fromJson(Map<String, dynamic> j) => CommitmentAction(
        name: j['name'] as String,
        amount: (j['amount'] as num).toDouble(),
        direction: ObligationDirection.fromValue((j['direction'] as String?) ?? 'out'),
        cadence: Cadence.fromValue((j['cadence'] as String?) ?? 'monthly'),
        nextDue: DateTime.parse(j['next_due'] as String),
        accountId: j['account_id'] as String?,
        accountName: j['account_name'] as String?,
      );
}
