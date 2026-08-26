import '../../features/accounts/domain/account.dart';
import '../../features/planning/domain/goal.dart';
import '../../features/planning/domain/obligation.dart';
import '../../features/transactions/domain/transaction.dart';

/// Turns raw balances and history into the handful of figures that actually
/// answer a question.
///
/// Everything here is pure and deterministic: same inputs, same numbers, no
/// network, no clock reads beyond the [asOf] you pass in. That matters because
/// these numbers are also what the coach is told — arithmetic happens here,
/// where it can be tested, and the model only gets to phrase the result.

/// Spending in one category over a window, against the same-length window
/// before it.
class CategorySpend {
  final String category;
  final double amount;
  final double previousAmount;

  const CategorySpend({
    required this.category,
    required this.amount,
    required this.previousAmount,
  });

  double get delta => amount - previousAmount;

  /// Change versus the previous window, as a fraction (0.38 == up 38%).
  /// Null when there is no prior spending to compare against.
  double? get changeRatio =>
      previousAmount <= 0 ? null : (amount - previousAmount) / previousAmount;
}

/// One account, with the part of its balance that is genuinely usable.
class AccountStanding {
  final Account account;

  /// Balance minus the floor the user set, never below zero.
  final double available;

  /// Obligations pinned to this account landing before the horizon.
  final double committed;

  const AccountStanding({
    required this.account,
    required this.available,
    required this.committed,
  });

  /// What could leave this account without breaking a floor or a known bill.
  double get freeToMove {
    final free = available - committed;
    return free > 0 ? free : 0;
  }

  bool get isBelowFloor => account.isBelowFloor;
}

class MoneySnapshot {
  final DateTime asOf;

  /// End of the window that [safeToSpend] and [committed] cover — normally the
  /// next expected income.
  final DateTime horizon;

  final double totalBalance;

  /// Split by how freely the money can be spent.
  final double liquid;
  final double reserved;
  final double locked;

  /// Sum of the minimum balances on liquid accounts.
  final double floors;

  /// Goal savings sitting inside the liquid pool, held back from spending.
  final double goalReserve;

  /// Bills landing between now and [horizon].
  final double committed;

  /// Expected inflows between now and [horizon]. Usually zero, since the
  /// horizon is normally the next inflow itself.
  final double expectedIncome;

  /// Liquid money left after floors, goals and everything already owed.
  /// This is the number that answers "can I afford this?".
  final double safeToSpend;

  /// Average real spending per day, from recent history. Transfers excluded.
  final double dailyBurn;

  /// Days the usable cash lasts at [dailyBurn]. Null when nothing is being
  /// spent, or infinite in practice.
  final double? runwayDays;

  /// Days until money is next expected to arrive. Null when nothing is known.
  final int? daysUntilIncome;

  final List<AccountStanding> standings;
  final List<CategorySpend> categories;

  /// Real spending and income over the trailing 30 days.
  final double spend30d;
  final double income30d;

  /// Real spending over the 30 days before those, so the dashboard can say
  /// whether this month is news rather than just how big it is.
  final double prevSpend30d;

  /// Change in spending against the previous 30 days, as a fraction. Null
  /// when there is nothing to compare against.
  double? get spendChangeRatio =>
      prevSpend30d <= 0 ? null : (spend30d - prevSpend30d) / prevSpend30d;

  const MoneySnapshot({
    required this.asOf,
    required this.horizon,
    required this.totalBalance,
    required this.liquid,
    required this.reserved,
    required this.locked,
    required this.floors,
    required this.goalReserve,
    required this.committed,
    required this.expectedIncome,
    required this.safeToSpend,
    required this.dailyBurn,
    required this.runwayDays,
    required this.daysUntilIncome,
    required this.standings,
    required this.categories,
    required this.spend30d,
    required this.income30d,
    required this.prevSpend30d,
  });

  /// Liquid money that is genuinely the user's to allocate — after floors and
  /// goals, but before bills. What [safeToSpend] is carved out of.
  double get usableCash => liquid - floors - goalReserve;

  /// True when the cash runs out before the next money arrives. The single most
  /// important thing the app can tell someone.
  bool get willFallShort {
    final r = runwayDays;
    final d = daysUntilIncome;
    if (r == null || d == null) return false;
    return r < d;
  }

  /// How many days short, when [willFallShort]. Zero otherwise.
  int get shortfallDays {
    if (!willFallShort) return 0;
    return (daysUntilIncome! - runwayDays!).ceil();
  }

  /// Accounts with money to spare, most first — the starting point for
  /// answering "where should I take this from?".
  List<AccountStanding> get movableSources {
    final out = standings
        .where((s) => !s.account.isArchived && s.freeToMove > 0)
        .toList()
      ..sort((a, b) => b.freeToMove.compareTo(a.freeToMove));
    return out;
  }
}

/// Number of days of history used to establish a spending rate.
const int kBurnWindowDays = 60;

/// Shortest horizon [safeToSpend] will ever cover, so an imminent payday does
/// not make things look artificially comfortable.
const int kMinHorizonDays = 7;

/// Horizon used when nothing is known about future income.
const int kDefaultHorizonDays = 30;

MoneySnapshot buildSnapshot({
  required List<Account> accounts,
  required List<Txn> txns,
  List<Obligation> obligations = const [],
  List<Goal> goals = const [],
  DateTime? now,
}) {
  final asOf = _dateOnly(now ?? DateTime.now());
  final live = accounts.where((a) => !a.isArchived).toList();
  final byId = {for (final a in live) a.id: a};

  // --- Where the money sits -------------------------------------------------
  double liquid = 0, reserved = 0, locked = 0, floors = 0;
  for (final a in live) {
    switch (a.liquidity) {
      case Liquidity.liquid:
        liquid += a.balance;
        floors += a.minBalance;
      case Liquidity.reserved:
        reserved += a.balance;
      case Liquidity.locked:
        locked += a.balance;
    }
  }
  final totalBalance = live.fold<double>(0, (s, a) => s + a.balance);

  // --- When does money next arrive? ----------------------------------------
  final activeObs = obligations.where((o) => o.isActive).toList();
  final incomeObs = activeObs.where((o) => !o.isOutflow);

  DateTime? nextIncome;
  for (final o in incomeObs) {
    final hit = o.nextOccurrenceOnOrAfter(asOf.add(const Duration(days: 1)));
    if (hit == null) continue;
    if (nextIncome == null || hit.isBefore(nextIncome)) nextIncome = hit;
  }

  final earliestHorizon = asOf.add(const Duration(days: kMinHorizonDays));
  final horizon = nextIncome == null
      ? asOf.add(const Duration(days: kDefaultHorizonDays))
      : (nextIncome.isBefore(earliestHorizon) ? earliestHorizon : nextIncome);

  final daysUntilIncome = nextIncome?.difference(asOf).inDays;

  // --- What is already spoken for ------------------------------------------
  final windowStart = asOf.add(const Duration(days: 1));
  double committed = 0, expectedIncome = 0;
  final committedByAccount = <String, double>{};

  for (final o in activeObs) {
    final due = o.amountDueBetween(windowStart, horizon);
    if (due <= 0) continue;
    if (o.isOutflow) {
      committed += due;
      final acc = o.accountId;
      if (acc != null && byId.containsKey(acc)) {
        committedByAccount[acc] = (committedByAccount[acc] ?? 0) + due;
      }
    } else {
      expectedIncome += due;
    }
  }

  // --- Money that exists but is not for spending ---------------------------
  //
  // Only count goal savings that actually sit in the liquid pool. A goal parked
  // in a locked account is already outside `liquid`, so reserving it again
  // would subtract the same money twice.
  double goalReserve = 0;
  for (final g in goals.where((g) => g.isActive)) {
    final acc = g.accountId;
    if (acc == null) {
      goalReserve += g.savedAmount;
      continue;
    }
    final home = byId[acc];
    if (home == null || home.liquidity == Liquidity.liquid) {
      goalReserve += g.savedAmount;
    }
  }

  final safeToSpend = liquid - floors - goalReserve - committed;

  // --- How fast money leaves ------------------------------------------------
  final burnStart = asOf.subtract(const Duration(days: kBurnWindowDays));
  final burnTxns =
      txns.where((t) => t.isSpending && !t.date.isBefore(burnStart) && !t.date.isAfter(asOf));
  final burnTotal = burnTxns.fold<double>(0, (s, t) => s + t.amount);

  // Measure over the history that exists, not the window we asked for —
  // otherwise a two-week-old account looks like it barely spends.
  final oldest = txns.where((t) => t.isSpending).fold<DateTime?>(
      null, (m, t) => m == null || t.date.isBefore(m) ? t.date : m);
  final observedDays = oldest == null
      ? kBurnWindowDays
      : asOf.difference(oldest.isBefore(burnStart) ? burnStart : oldest).inDays + 1;
  final dailyBurn = observedDays <= 0 ? 0.0 : burnTotal / observedDays;

  final usableCash = liquid - floors - goalReserve;
  final runwayDays =
      dailyBurn <= 0 ? null : (usableCash <= 0 ? 0.0 : usableCash / dailyBurn);

  // --- Per-account standing -------------------------------------------------
  final standings = [
    for (final a in live)
      AccountStanding(
        account: a,
        available: a.available,
        committed: committedByAccount[a.id] ?? 0,
      ),
  ]..sort((x, y) => y.freeToMove.compareTo(x.freeToMove));

  // --- Trailing 30 days and category movement ------------------------------
  final cut30 = asOf.subtract(const Duration(days: 30));
  final cut60 = asOf.subtract(const Duration(days: 60));

  double spend30d = 0, income30d = 0, prevSpend30d = 0;
  final current = <String, double>{};
  final previous = <String, double>{};

  for (final t in txns) {
    if (!t.isRealMoneyMovement) continue;
    final inCurrent = !t.date.isBefore(cut30) && !t.date.isAfter(asOf);
    final inPrevious = !t.date.isBefore(cut60) && t.date.isBefore(cut30);
    if (t.isIncome && inCurrent) income30d += t.amount;
    if (!t.isSpending) continue;
    if (inCurrent) {
      spend30d += t.amount;
      current[t.category] = (current[t.category] ?? 0) + t.amount;
    } else if (inPrevious) {
      prevSpend30d += t.amount;
      previous[t.category] = (previous[t.category] ?? 0) + t.amount;
    }
  }

  final categories = [
    for (final e in current.entries)
      CategorySpend(
        category: e.key,
        amount: e.value,
        previousAmount: previous[e.key] ?? 0,
      ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));

  return MoneySnapshot(
    asOf: asOf,
    horizon: horizon,
    totalBalance: totalBalance,
    liquid: liquid,
    reserved: reserved,
    locked: locked,
    floors: floors,
    goalReserve: goalReserve,
    committed: committed,
    expectedIncome: expectedIncome,
    safeToSpend: safeToSpend,
    dailyBurn: dailyBurn,
    runwayDays: runwayDays,
    daysUntilIncome: daysUntilIncome,
    standings: standings,
    categories: categories,
    spend30d: spend30d,
    income30d: income30d,
    prevSpend30d: prevSpend30d,
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
