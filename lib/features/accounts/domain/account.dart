/// What kind of place the money sits in. Drives fees, access speed and the
/// default advice about whether to touch it.
enum AccountKind {
  bank('bank', 'Bank'),
  momo('momo', 'Mobile Money'),
  cash('cash', 'Cash'),
  savings('savings', 'Savings'),
  investment('investment', 'Investment'),
  credit('credit', 'Credit');

  final String value;
  final String label;
  const AccountKind(this.value, this.label);

  static AccountKind fromValue(String s) =>
      values.firstWhere((k) => k.value == s, orElse: () => AccountKind.bank);
}

/// How freely this money can be spent. The difference between a balance and a
/// balance you are actually allowed to use.
enum Liquidity {
  /// Spend it today without consequence.
  liquid('liquid', 'Spendable'),

  /// It is there, but it is meant for something. Spendable under protest.
  reserved('reserved', 'Reserved'),

  /// Do not raid this — fixed deposit, investment, long-term savings.
  locked('locked', 'Locked');

  final String value;
  final String label;
  const Liquidity(this.value, this.label);

  static Liquidity fromValue(String s) =>
      values.firstWhere((l) => l.value == s, orElse: () => Liquidity.liquid);
}

class Account {
  final String id;
  final String userId;
  final String name;
  final double balance;
  final AccountKind kind;
  final Liquidity liquidity;

  /// Floor this account should not drop below. Money below it is off-limits
  /// even when the account is liquid.
  final double minBalance;

  /// Free text the user writes about what this account is for. Fed to the
  /// coach so it can reason the way the user does ("Momo pays rent").
  final String? purpose;

  /// Balance that predates the transaction history. Kept separate so
  /// recomputing from transactions never erases it.
  final double openingBalance;

  final bool isArchived;
  final int sortOrder;
  final DateTime createdAt;

  const Account({
    required this.id,
    required this.userId,
    required this.name,
    required this.balance,
    required this.kind,
    required this.liquidity,
    required this.minBalance,
    required this.purpose,
    required this.openingBalance,
    required this.isArchived,
    required this.sortOrder,
    required this.createdAt,
  });

  /// What you could take out of here right now without breaking the floor.
  /// Never negative — an account already under its floor offers nothing.
  double get available {
    final free = balance - minBalance;
    return free > 0 ? free : 0;
  }

  /// Whether this account should be considered for day-to-day spending at all.
  bool get isSpendable => !isArchived && liquidity == Liquidity.liquid;

  /// True when the account has dipped below the floor the user set for it.
  bool get isBelowFloor => minBalance > 0 && balance < minBalance;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        name: j['name'] as String,
        balance: (j['balance'] as num).toDouble(),
        kind: AccountKind.fromValue((j['kind'] as String?) ?? 'bank'),
        liquidity: Liquidity.fromValue((j['liquidity'] as String?) ?? 'liquid'),
        minBalance: (j['min_balance'] as num?)?.toDouble() ?? 0,
        purpose: j['purpose'] as String?,
        openingBalance: (j['opening_balance'] as num?)?.toDouble() ?? 0,
        isArchived: (j['is_archived'] as bool?) ?? false,
        sortOrder: (j['sort_order'] as int?) ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Account copyWith({
    String? name,
    double? balance,
    AccountKind? kind,
    Liquidity? liquidity,
    double? minBalance,
    String? purpose,
    double? openingBalance,
    bool? isArchived,
    int? sortOrder,
  }) =>
      Account(
        id: id,
        userId: userId,
        name: name ?? this.name,
        balance: balance ?? this.balance,
        kind: kind ?? this.kind,
        liquidity: liquidity ?? this.liquidity,
        minBalance: minBalance ?? this.minBalance,
        purpose: purpose ?? this.purpose,
        openingBalance: openingBalance ?? this.openingBalance,
        isArchived: isArchived ?? this.isArchived,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );
}
