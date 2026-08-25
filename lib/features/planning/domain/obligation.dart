/// How often an obligation repeats.
enum Cadence {
  once('once', 'One-off'),
  weekly('weekly', 'Weekly'),
  biweekly('biweekly', 'Every 2 weeks'),
  monthly('monthly', 'Monthly'),
  quarterly('quarterly', 'Quarterly'),
  yearly('yearly', 'Yearly');

  final String value;
  final String label;
  const Cadence(this.value, this.label);

  static Cadence fromValue(String s) =>
      values.firstWhere((c) => c.value == s, orElse: () => Cadence.monthly);
}

/// Which way the money flows.
enum ObligationDirection {
  /// A bill, rent, subscription — money you already owe.
  out('out', 'Bill'),

  /// Salary or any inflow you can count on. Needed to answer "how long until
  /// more money arrives?", which is what makes a runway figure meaningful.
  incoming('in', 'Expected income');

  final String value;
  final String label;
  const ObligationDirection(this.value, this.label);

  static ObligationDirection fromValue(String s) =>
      values.firstWhere((d) => d.value == s, orElse: () => ObligationDirection.out);
}

/// Money that is already spoken for, or already on its way.
///
/// This is what turns a balance into an answer. Without it, GHS 3,000 in the
/// bank and GHS 3,000 with rent due Friday look identical.
class Obligation {
  final String id;
  final String userId;
  final String name;
  final ObligationDirection direction;
  final double amount;
  final Cadence cadence;

  /// The next (or only) time this lands. Recurrence rolls forward from here.
  final DateTime nextDue;

  /// Which account it is paid from, or arrives into. Null means "not decided",
  /// in which case it counts against the liquid pool as a whole.
  final String? accountId;

  final String? category;
  final bool isActive;
  final DateTime createdAt;

  const Obligation({
    required this.id,
    required this.userId,
    required this.name,
    required this.direction,
    required this.amount,
    required this.cadence,
    required this.nextDue,
    required this.accountId,
    required this.category,
    required this.isActive,
    required this.createdAt,
  });

  bool get isOutflow => direction == ObligationDirection.out;

  /// Every time this obligation lands in `[from, to]`, inclusive.
  ///
  /// Rolls forward from [nextDue] and, for anything already in the past, rolls
  /// forward to catch up first — so a monthly bill whose anchor was set months
  /// ago still reports its upcoming dates correctly.
  List<DateTime> occurrencesBetween(DateTime from, DateTime to) {
    final start = _dateOnly(from);
    final end = _dateOnly(to);
    if (end.isBefore(start)) return const [];

    var cursor = _dateOnly(nextDue);
    final out = <DateTime>[];

    if (cadence == Cadence.once) {
      if (!cursor.isBefore(start) && !cursor.isAfter(end)) out.add(cursor);
      return out;
    }

    // Catch up to the window without emitting anything before it.
    var guard = 0;
    while (cursor.isBefore(start) && guard++ < 1200) {
      cursor = _advance(cursor);
    }

    guard = 0;
    while (!cursor.isAfter(end) && guard++ < 1200) {
      out.add(cursor);
      cursor = _advance(cursor);
    }
    return out;
  }

  /// Total landing in `[from, to]`, as a positive number.
  double amountDueBetween(DateTime from, DateTime to) =>
      occurrencesBetween(from, to).length * amount;

  /// The first time this lands on or after [from], if ever.
  DateTime? nextOccurrenceOnOrAfter(DateTime from) {
    final hits = occurrencesBetween(from, from.add(const Duration(days: 400)));
    return hits.isEmpty ? null : hits.first;
  }

  DateTime _advance(DateTime d) => switch (cadence) {
        Cadence.once => d.add(const Duration(days: 36500)),
        Cadence.weekly => d.add(const Duration(days: 7)),
        Cadence.biweekly => d.add(const Duration(days: 14)),
        Cadence.monthly => _addMonths(d, 1),
        Cadence.quarterly => _addMonths(d, 3),
        Cadence.yearly => _addMonths(d, 12),
      };

  factory Obligation.fromJson(Map<String, dynamic> j) => Obligation(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        name: j['name'] as String,
        direction: ObligationDirection.fromValue((j['direction'] as String?) ?? 'out'),
        amount: (j['amount'] as num).toDouble(),
        cadence: Cadence.fromValue((j['cadence'] as String?) ?? 'monthly'),
        nextDue: DateTime.parse(j['next_due'] as String),
        accountId: j['account_id'] as String?,
        category: j['category'] as String?,
        isActive: (j['is_active'] as bool?) ?? true,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Adds months, clamping the day to the target month's length so the 31st of
/// January lands on the 28th/29th of February rather than overflowing to March.
DateTime _addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  final year = d.year + (total ~/ 12);
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day < lastDay ? d.day : lastDay);
}
