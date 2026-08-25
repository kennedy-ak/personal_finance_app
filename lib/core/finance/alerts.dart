import '../../features/planning/domain/goal.dart';
import '../../features/planning/domain/obligation.dart';
import '../formatters.dart';
import 'money_engine.dart';

/// Things worth telling the user, worked out in Dart.
///
/// Detection is deterministic on purpose. A model asked to spot problems will
/// invent them; a rule that fires on `runway < daysUntilIncome` cannot. When the
/// coach eventually phrases these, it gets the finished sentence and the exact
/// numbers — it decides the wording, never the fact.

enum AlertSeverity {
  /// Something will go wrong unless the user acts.
  critical,

  /// Worth looking at now.
  warning,

  /// Useful to know.
  info,
}

class MoneyAlert {
  /// Stable across rebuilds, so the UI can dismiss or animate consistently.
  final String id;
  final AlertSeverity severity;

  /// The verb. What to do, not what happened.
  final String title;

  /// The evidence, with real figures.
  final String detail;

  /// Where tapping it should take the user, if anywhere.
  final String? actionLabel;
  final String? actionRoute;

  const MoneyAlert({
    required this.id,
    required this.severity,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.actionRoute,
  });
}

/// A category has to move by at least this fraction *and* this many cedis
/// before it is worth mentioning. Percentages alone make small categories
/// scream.
const double kCategorySpikeRatio = 0.35;
const double kCategorySpikeFloor = 100;

/// How far ahead to warn about a bill whose account cannot cover it.
const int kBillWarningDays = 7;

/// Idle cash is only worth flagging once it is a meaningful sum.
const double kIdleCashFloor = 500;

List<MoneyAlert> buildAlerts({
  required MoneySnapshot snapshot,
  List<Obligation> obligations = const [],
  List<Goal> goals = const [],
  DateTime? now,
}) {
  final asOf = now == null
      ? snapshot.asOf
      : DateTime(now.year, now.month, now.day);
  final out = <MoneyAlert>[];

  out.addAll(_setupGaps(snapshot, obligations));
  out.addAll(_shortfall(snapshot));
  out.addAll(_overcommitted(snapshot));
  out.addAll(_accountsBelowFloor(snapshot));
  out.addAll(_billsWithoutCover(snapshot, obligations, asOf));
  out.addAll(_categorySpikes(snapshot));
  out.addAll(_idleCash(snapshot, goals));

  // Loudest first — a dashboard that buries the emergency is no better than one
  // that never noticed it.
  out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return out;
}

/// The app cannot judge anything without knowing when money arrives. Say so
/// plainly rather than quietly reporting a meaningless runway.
List<MoneyAlert> _setupGaps(MoneySnapshot s, List<Obligation> obligations) {
  final hasIncome =
      obligations.any((o) => o.isActive && !o.isOutflow);
  if (hasIncome) return const [];

  return [
    const MoneyAlert(
      id: 'setup.no-income',
      severity: AlertSeverity.info,
      title: 'Tell the app when you get paid',
      detail:
          'Without an expected income date there is no way to know whether your '
          'money has to last three days or thirty.',
      actionLabel: 'Add income',
      actionRoute: '/plan',
    ),
  ];
}

/// The headline failure: the money runs out before more arrives.
List<MoneyAlert> _shortfall(MoneySnapshot s) {
  if (!s.willFallShort) return const [];

  final days = s.daysUntilIncome!;
  final sustainable = days <= 0 ? 0.0 : s.usableCash / days;
  final cut = s.dailyBurn - sustainable;

  return [
    MoneyAlert(
      id: 'cash.shortfall',
      severity: AlertSeverity.critical,
      title: 'You run out ${s.shortfallDays} days before payday',
      detail: 'At ${_money(s.dailyBurn)} a day your ${_money(s.usableCash)} lasts '
          '${s.runwayDays!.floor()} days, and income is $days days away. '
          'Spending ${_money(sustainable)} a day instead closes the gap — '
          'about ${_money(cut)} less each day.',
      actionLabel: 'See spending',
      actionRoute: '/history',
    ),
  ];
}

/// Bills already exceed what is spendable, regardless of pace.
List<MoneyAlert> _overcommitted(MoneySnapshot s) {
  if (s.safeToSpend >= 0) return const [];

  return [
    MoneyAlert(
      id: 'cash.overcommitted',
      severity: AlertSeverity.critical,
      title: 'Your bills exceed your spendable money by ${_money(-s.safeToSpend)}',
      detail: '${_money(s.usableCash)} is available and ${_money(s.committed)} is '
          'already committed before ${_shortDate(s.horizon)}. Something has to '
          'move — a locked account, a goal, or a bill date.',
      actionLabel: 'Review commitments',
      actionRoute: '/plan',
    ),
  ];
}

/// An account the user asked to protect has been dipped into.
List<MoneyAlert> _accountsBelowFloor(MoneySnapshot s) {
  final out = <MoneyAlert>[];

  for (final standing in s.standings.where((x) => x.isBelowFloor)) {
    final a = standing.account;
    final gap = a.minBalance - a.balance;
    final source = _bestSourceExcluding(s, a.id, gap);

    out.add(MoneyAlert(
      id: 'account.below-floor.${a.id}',
      severity: AlertSeverity.warning,
      title: source == null
          ? '${a.name} is below the floor you set'
          : 'Move ${_money(gap)} from ${source.account.name} to ${a.name}',
      detail: '${a.name} holds ${_money(a.balance)} but you asked to keep at '
          'least ${_money(a.minBalance)}'
          '${source == null ? '. No other account has ${_money(gap)} free.' : '.'}',
      actionLabel: source == null ? null : 'Transfer',
      actionRoute: source == null ? null : '/add',
    ));
  }
  return out;
}

/// A bill is about to leave an account that cannot cover it — the exact
/// situation where knowing early is worth everything.
List<MoneyAlert> _billsWithoutCover(
  MoneySnapshot s,
  List<Obligation> obligations,
  DateTime asOf,
) {
  final out = <MoneyAlert>[];
  final deadline = asOf.add(const Duration(days: kBillWarningDays));
  final standings = {for (final x in s.standings) x.account.id: x};

  for (final o in obligations.where((o) => o.isActive && o.isOutflow)) {
    final acc = o.accountId;
    if (acc == null) continue;
    final standing = standings[acc];
    if (standing == null) continue;

    final due = o.nextOccurrenceOnOrAfter(asOf);
    if (due == null || due.isAfter(deadline)) continue;
    if (standing.available >= o.amount) continue;

    final gap = o.amount - standing.available;
    final source = _bestSourceExcluding(s, acc, gap);
    final daysAway = due.difference(asOf).inDays;
    final when = daysAway <= 0 ? 'today' : 'in $daysAway days';

    out.add(MoneyAlert(
      id: 'bill.uncovered.${o.id}',
      severity: AlertSeverity.critical,
      title: source == null
          ? '${o.name} will bounce $when'
          : 'Move ${_money(gap)} to ${standing.account.name} before ${o.name}',
      detail: '${o.name} takes ${_money(o.amount)} from '
          '${standing.account.name} $when, but only ${_money(standing.available)} '
          'is free there'
          '${source == null ? ' and nothing else has ${_money(gap)} spare.' : '. ${source.account.name} has ${_money(source.freeToMove)} spare.'}',
      actionLabel: source == null ? 'Review' : 'Transfer',
      actionRoute: source == null ? '/plan' : '/add',
    ));
  }
  return out;
}

/// What changed, which is the thing a list of numbers never tells you.
List<MoneyAlert> _categorySpikes(MoneySnapshot s) {
  final out = <MoneyAlert>[];

  for (final c in s.categories) {
    final ratio = c.changeRatio;
    if (ratio == null || ratio < kCategorySpikeRatio) continue;
    if (c.delta < kCategorySpikeFloor) continue;

    out.add(MoneyAlert(
      id: 'category.spike.${c.category}',
      severity: AlertSeverity.warning,
      title: '${c.category} is up ${(ratio * 100).round()}% this month',
      detail: '${_money(c.amount)} in the last 30 days against '
          '${_money(c.previousAmount)} the 30 days before — '
          '${_money(c.delta)} more.',
      actionLabel: 'See transactions',
      actionRoute: '/history',
    ));
  }

  // One spike is a signal; five is noise.
  return out.take(2).toList();
}

/// Money sitting in a current account while a goal goes unfunded.
List<MoneyAlert> _idleCash(MoneySnapshot s, List<Goal> goals) {
  if (s.safeToSpend < kIdleCashFloor) return const [];

  final underfunded = goals
      .where((g) => g.isActive && !g.isComplete)
      .toList()
    ..sort((a, b) => a.priority.compareTo(b.priority));
  if (underfunded.isEmpty) return const [];

  final goal = underfunded.first;
  // Never suggest moving money the user still needs to live on.
  final spare = s.safeToSpend - (s.dailyBurn * 14);
  if (spare < kIdleCashFloor) return const [];

  final amount = spare < goal.remaining ? spare : goal.remaining;

  return [
    MoneyAlert(
      id: 'goal.top-up.${goal.id}',
      severity: AlertSeverity.info,
      title: 'Put ${_money(amount)} towards ${goal.name}',
      detail: 'You have ${_money(s.safeToSpend)} spendable and only need about '
          '${_money(s.dailyBurn * 14)} for the next two weeks. '
          '${goal.name} still needs ${_money(goal.remaining)}.',
      actionLabel: 'Open goals',
      actionRoute: '/plan',
    ),
  ];
}

/// The account best placed to give up [amount], ignoring [excludeId].
AccountStanding? _bestSourceExcluding(
  MoneySnapshot s,
  String excludeId,
  double amount,
) {
  for (final candidate in s.movableSources) {
    if (candidate.account.id == excludeId) continue;
    if (candidate.freeToMove >= amount) return candidate;
  }
  return null;
}

String _money(double v) => formatMoney(v);

String _shortDate(DateTime d) => dateLongFmt.format(d);
