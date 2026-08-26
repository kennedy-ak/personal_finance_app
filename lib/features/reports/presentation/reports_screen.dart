import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _tab = 0;
  DateTime _selectedWeek = weekStart(DateTime.now());

  static DateTime weekStart(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final txns = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Reports', style: AppType.title.copyWith(color: t.ink)),
                  const SizedBox(height: 18),
                  SegmentedTabs(
                    labels: const ['This week', 'Trends', 'Detailed'],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ],
              ),
            ),
            Expanded(
              child: txns.when(
                loading: () =>
                    Center(child: CircularProgressIndicator(color: t.brandInk)),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorCard(
                    title: 'Could not load your transactions',
                    message: 'Check your connection and try again.',
                    onRetry: () => bumpTransactions(ref),
                  ),
                ),
                data: (list) => switch (_tab) {
                  0 => _CurrentWeekTab(transactions: list),
                  1 => _TrendsTab(transactions: list),
                  _ => _DetailedTab(
                      transactions: list,
                      week: _selectedWeek,
                      onStep: (delta) => setState(() => _selectedWeek =
                          _selectedWeek.add(Duration(days: 7 * delta))),
                      onPick: (d) =>
                          setState(() => _selectedWeek = weekStart(d)),
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekStats {
  final double income;
  final double expense;
  final int count;
  const _WeekStats(this.income, this.expense, this.count);
  double get net => income - expense;
}

_WeekStats _statsFor(List<Txn> txns, DateTime weekStart) {
  final end = weekStart.add(const Duration(days: 7));
  return _statsBetween(txns, weekStart, end);
}

_WeekStats _statsBetween(List<Txn> txns, DateTime from, DateTime to) {
  double inc = 0, exp = 0;
  int n = 0;
  for (final t in txns) {
    if (!t.isRealMoneyMovement) continue;
    if (!t.date.isBefore(from) && t.date.isBefore(to)) {
      if (t.isIncome) {
        inc += t.amount;
      } else {
        exp += t.amount;
      }
      n++;
    }
  }
  return _WeekStats(inc, exp, n);
}

/// The verdict card that opens This week and Trends: an eyebrow, a figure, and
/// a line of context. Green when the period came out ahead, red when it did
/// not — never a gradient, and never white text on either.
class _NetHero extends StatelessWidget {
  final String eyebrow;
  final double net;
  final String caption;

  const _NetHero({
    required this.eyebrow,
    required this.net,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final positive = net >= 0;
    final tint = positive ? t.safe : t.expense;

    return TintCard(
      tint: tint,
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(eyebrow,
              color: positive
                  ? (dark ? const Color(0xFF6FDCBF) : tint.ink)
                  : tint.muted),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(positive ? kCurrencyCode : '-$kCurrencyCode',
                  style: AppType.heroCode
                      .copyWith(fontSize: 15, color: tint.muted)),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    moneyDigits(net.abs()),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.heroFigure
                        .copyWith(fontSize: 38, color: tint.ink),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(caption,
              style: AppType.bodySmall.copyWith(height: 1.4, color: tint.body)),
        ],
      ),
    );
  }
}

/// The three-up row, solved at worst case.
///
/// `-GHS 12,480.00` does not fit a third of a 390pt screen on one line, so the
/// currency code goes on its own line above the digits and the digits get the
/// full column. Nothing truncates, at any figure the app can produce.
class _FigureRow extends StatelessWidget {
  final _WeekStats stats;
  const _FigureRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    // IntrinsicHeight because this row is dropped straight into a ListView,
    // where the incoming height is unbounded and a stretching Row would pass
    // an infinite tight constraint down to the cards.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FigureCard(
                label: 'Income', amount: stats.income, tint: t.income),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FigureCard(
                label: 'Expense',
                amount: stats.expense,
                tint: t.expense,
                negate: true),
          ),
          const SizedBox(width: 8),
          Expanded(
            // Net takes the neutral tint whatever its sign. A green card and a
            // red card either side of it already say which way the week went;
            // colouring the verdict too turns the row into a traffic light.
            child: FigureCard(label: 'Net', amount: stats.net, tint: t.neutral),
          ),
        ],
      ),
    );
  }
}

class _CurrentWeekTab extends StatelessWidget {
  final List<Txn> transactions;
  const _CurrentWeekTab({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final start = _ReportsScreenState.weekStart(DateTime.now());
    final end = start.add(const Duration(days: 6));
    final stats = _statsFor(transactions, start);

    final daily = List.filled(7, 0.0);
    for (final txn in transactions) {
      if (!txn.isSpending) continue;
      final i = txn.date.difference(start).inDays;
      if (i >= 0 && i < 7) daily[i] += txn.amount;
    }
    final peak = daily.fold<double>(0, (m, v) => v > m ? v : m);

    return ListView(
      // Clears the docked add button at the bottom of the screen.
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
      children: [
        _NetHero(
          eyebrow: 'Net this week',
          net: stats.net,
          caption: '${dayMonthFmt.format(start)} – ${dayMonthFmt.format(end)} · '
              '${stats.count} transaction${stats.count == 1 ? '' : 's'}',
        ),
        const SizedBox(height: 18),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FigureCard(
                    label: 'Income',
                    amount: stats.income,
                    tint: t.income,
                    large: true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FigureCard(
                    label: 'Expense',
                    amount: stats.expense,
                    tint: t.expense,
                    large: true,
                    negate: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        CediCard(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionRow(
                title: 'Daily spend',
                note: peak <= 0 ? 'NOTHING SPENT' : 'PEAK ${formatMoney(peak)}',
              ),
              const SizedBox(height: 18),
              _DailyBars(values: daily, weekStart: start),
            ],
          ),
        ),
      ],
    );
  }
}

/// Seven bars, one per day, with the heaviest day picked out.
///
/// Drawn rather than charted: seven values need a row of rectangles, not a
/// chart library with axes, tooltips and a legend.
class _DailyBars extends StatelessWidget {
  final List<double> values;
  final DateTime weekStart;

  const _DailyBars({required this.values, required this.weekStart});

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final peak = values.fold<double>(0, (m, v) => v > m ? v : m);
    final today = DateTime.now();
    final todayIndex = DateTime(today.year, today.month, today.day)
        .difference(weekStart)
        .inDays;

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            Expanded(
              child: Tooltip(
                message: '${_labels[i]} · ${formatMoney(values[i])}',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A day with nothing spent still gets a sliver, so the
                    // row reads as seven days rather than four.
                    SizedBox(
                      height: peak <= 0
                          ? 3
                          : (values[i] / peak * 120).clamp(3.0, 120.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: values[i] >= peak && peak > 0
                              ? t.brandInk
                              : t.brand.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _labels[i],
                      style: AppType.label.copyWith(
                        fontSize: 11,
                        color: i == todayIndex ? t.ink : t.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthStat {
  final DateTime month;
  final double income;
  final double expense;
  const _MonthStat(this.month, this.income, this.expense);
  double get net => income - expense;
}

class _TrendsTab extends StatelessWidget {
  final List<Txn> transactions;
  const _TrendsTab({required this.transactions});

  List<_MonthStat> get _months {
    final now = DateTime.now();
    return [
      for (var back = 5; back >= 0; back--)
        () {
          final from = DateTime(now.year, now.month - back, 1);
          final to = DateTime(now.year, now.month - back + 1, 1);
          final s = _statsBetween(transactions, from, to);
          return _MonthStat(from, s.income, s.expense);
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final months = _months;
    final current = months.last;
    final previous = months.length > 1 ? months[months.length - 2] : null;

    final withSpend = months.where((m) => m.expense > 0).toList();
    final avgSpend = withSpend.isEmpty
        ? 0.0
        : withSpend.fold<double>(0, (s, m) => s + m.expense) / withSpend.length;

    final best = months.reduce((a, b) => b.net > a.net ? b : a);
    final negatives = months.where((m) => m.net < 0).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
      children: [
        CediCard(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Net by month',
                  style: AppType.cardTitle.copyWith(color: t.ink)),
              const SizedBox(height: 4),
              Text(
                'Six months. Bars below the line are months you spent more '
                'than you earned.',
                style: AppType.rowSub.copyWith(height: 1.4, color: t.inkMuted),
              ),
              const SizedBox(height: 18),
              _NetByMonth(months: months),
            ],
          ),
        ),
        const SizedBox(height: 18),
        CediCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Month over month',
                  style: AppType.cardTitle.copyWith(color: t.ink)),
              const SizedBox(height: 14),
              _TrendRow(
                label: '${monthFmt.format(current.month)} net',
                value: formatMoney(current.net),
                delta: previous == null || previous.net == 0
                    ? null
                    : (current.net - previous.net) / previous.net.abs(),
                deltaUpIsGood: true,
              ),
              const SizedBox(height: 12),
              _TrendRow(
                label: 'Average spend',
                value: formatMoney(avgSpend),
                delta: avgSpend <= 0
                    ? null
                    : (current.expense - avgSpend) / avgSpend,
                deltaUpIsGood: false,
              ),
              const SizedBox(height: 12),
              _TrendRow(
                label: 'Best month',
                value: formatMoney(best.net),
                note: monthFmt.format(best.month),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TintCard(
          tint: t.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('Reading', color: t.accent.ink),
              const SizedBox(height: 8),
              Text(
                _reading(months, negatives, current),
                style: AppType.body.copyWith(height: 1.5, color: t.accent.body),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One sentence about the shape of the six months, worked out here rather
  /// than by the coach — it is arithmetic, not judgement, so it does not need
  /// a model and it is never wrong.
  String _reading(
      List<_MonthStat> months, int negatives, _MonthStat current) {
    if (months.every((m) => m.income == 0 && m.expense == 0)) {
      return 'Nothing logged in the last six months yet. Once a couple of '
          'months are in, this reads the shape of them for you.';
    }
    if (negatives == 0) {
      return 'Every one of the last six months ended positive. '
          '${monthFmt.format(current.month)} is running at '
          '${formatMoney(current.net)}.';
    }
    final worst = months.reduce((a, b) => b.net < a.net ? b : a);
    return '$negatives of the last six months ended negative, the deepest '
        '${monthFmt.format(worst.month)} at ${formatMoney(worst.net)}. '
        '${monthFmt.format(current.month)} is at '
        '${formatMoney(current.net)} so far.';
  }
}

/// Bars above and below a zero rule. The sign is carried by which side of the
/// line the bar sits on, and reinforced by colour — not by colour alone.
class _NetByMonth extends StatelessWidget {
  final List<_MonthStat> months;
  const _NetByMonth({required this.months});

  @override
  Widget build(BuildContext context) {
    final peak = months.fold<double>(
        0, (m, s) => s.net.abs() > m ? s.net.abs() : m);

    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < months.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            Expanded(
              child: Tooltip(
                message: '${monthFmt.format(months[i].month)} · '
                    '${formatMoney(months[i].net)}',
                child: _MonthBar(
                  stat: months[i],
                  peak: peak,
                  latest: i == months.length - 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  final _MonthStat stat;
  final double peak;
  final bool latest;

  const _MonthBar(
      {required this.stat, required this.peak, required this.latest});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final positive = stat.net >= 0;
    final fraction = peak <= 0 ? 0.0 : (stat.net.abs() / peak).clamp(0.0, 1.0);
    final full = positive ? t.income.ink : t.expense.ink;
    final colour = latest ? full : full.withValues(alpha: 0.5);

    Widget half(bool filled, bool top) => Expanded(
          child: filled
              ? Align(
                  alignment:
                      top ? Alignment.bottomCenter : Alignment.topCenter,
                  child: FractionallySizedBox(
                    heightFactor: fraction == 0 ? 0.02 : fraction,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colour,
                        borderRadius: top
                            ? const BorderRadius.vertical(
                                top: Radius.circular(7))
                            : const BorderRadius.vertical(
                                bottom: Radius.circular(7)),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        );

    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              half(positive, true),
              Container(height: 1, color: t.outline),
              half(!positive, false),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          monthFmt.format(stat.month),
          style: AppType.navLabel
              .copyWith(color: latest ? t.ink : t.inkMuted),
        ),
      ],
    );
  }
}

class _TrendRow extends StatelessWidget {
  final String label;
  final String value;
  final double? delta;
  final String? note;

  /// Up is good for net, bad for spend. Colour follows meaning, not direction.
  final bool deltaUpIsGood;

  const _TrendRow({
    required this.label,
    required this.value,
    this.delta,
    this.note,
    this.deltaUpIsGood = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final d = delta;
    final good = d == null ? true : (d >= 0) == deltaUpIsGood;

    return Row(
      children: [
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodySmall.copyWith(height: 1.0, color: t.inkBody)),
        ),
        const SizedBox(width: 10),
        Text(value,
            softWrap: false,
            style: AppType.figureRow.copyWith(fontSize: 13, color: t.ink)),
        SizedBox(
          width: 58,
          child: Text(
            d != null
                ? '${d >= 0 ? '+' : '−'}${(d.abs() * 100).round()}%'
                : (note ?? ''),
            textAlign: TextAlign.right,
            style: AppType.label.copyWith(
              fontSize: 12,
              color: d == null
                  ? t.inkMuted
                  : good
                      ? t.income.ink
                      : t.expense.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailedTab extends ConsumerWidget {
  final List<Txn> transactions;
  final DateTime week;
  final ValueChanged<int> onStep;
  final ValueChanged<DateTime> onPick;

  const _DetailedTab({
    required this.transactions,
    required this.week,
    required this.onStep,
    required this.onPick,
  });

  /// ISO-ish week number, good enough to name the row the user is looking at.
  static int _weekOfYear(DateTime d) {
    final firstDay = DateTime(d.year, 1, 1);
    return ((d.difference(firstDay).inDays + firstDay.weekday) / 7).ceil();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final end = week.add(const Duration(days: 6));
    final stats = _statsFor(transactions, week);
    final inWeek = transactions
        .where((txn) =>
            !txn.date.isBefore(week) &&
            txn.date.isBefore(week.add(const Duration(days: 7))))
        .toList();

    final byCat = <String, double>{};
    for (final txn in inWeek.where((x) => x.isSpending)) {
      byCat[txn.category] = (byCat[txn.category] ?? 0) + txn.amount;
    }
    final catEntries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final accounts = ref.watch(accountsProvider).value ?? [];
    final byAcc = {
      for (final a in accounts)
        a.id: _statsFor(
            inWeek.where((txn) => txn.accountId == a.id).toList(), week),
    };
    final active =
        accounts.where((a) => (byAcc[a.id]?.count ?? 0) > 0).toList();

    final nextWeek = week.add(const Duration(days: 7));
    final canGoForward = !nextWeek.isAfter(DateTime.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
      children: [
        PeriodStepper(
          title: '${dayMonthFmt.format(week)} – ${dayMonthFmt.format(end)}',
          caption: 'Week ${_weekOfYear(week)}',
          onPrevious: () => onStep(-1),
          onNext: canGoForward ? () => onStep(1) : null,
          onTapTitle: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: week,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) onPick(picked);
          },
        ),
        const SizedBox(height: 14),
        _FigureRow(stats: stats),
        const SizedBox(height: 18),
        CediCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionRow(
                  title: 'By category', note: 'SHARE OF EXPENSES'),
              const SizedBox(height: 14),
              if (catEntries.isEmpty)
                Text('No expenses in this week.',
                    style: AppType.bodySmall.copyWith(color: t.inkMuted))
              else ...[
                StackedBar(
                  height: 10,
                  slices: [
                    for (var i = 0; i < catEntries.length; i++)
                      BarSlice(catEntries[i].value,
                          AppColors.chart[i % AppColors.chart.length]),
                  ],
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < catEntries.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  LegendLine(
                    color: AppColors.chart[i % AppColors.chart.length],
                    label: catEntries[i].key,
                    middle: stats.expense <= 0
                        ? null
                        : '${(catEntries[i].value / stats.expense * 100).round()}%',
                    trailing: formatMoney(catEntries[i].value),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        CediCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionRow(title: 'By account'),
              const SizedBox(height: 14),
              if (active.isEmpty)
                Text('Nothing moved through your accounts this week.',
                    style: AppType.bodySmall.copyWith(color: t.inkMuted))
              else
                for (var i = 0; i < active.length; i++) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 14),
                    Container(height: 1, color: t.rule),
                    const SizedBox(height: 14),
                  ],
                  _AccountBlock(
                      name: active[i].name, stats: byAcc[active[i].id]!),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One account's week: the net at the top, then what came in and what left.
class _AccountBlock extends StatelessWidget {
  final String name;
  final _WeekStats stats;

  const _AccountBlock({required this.name, required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowTitle.copyWith(height: 1.0, color: t.ink)),
            ),
            const SizedBox(width: 10),
            Text(formatMoney(stats.net),
                softWrap: false,
                style: AppType.figureRow.copyWith(
                  color: stats.net >= 0 ? t.ink : t.expense.ink,
                )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _FlowChip(
                  label: 'In', amount: stats.income, tint: t.income),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FlowChip(
                  label: 'Out', amount: -stats.expense, tint: t.expense),
            ),
          ],
        ),
      ],
    );
  }
}

class _FlowChip extends StatelessWidget {
  final String label;
  final double amount;
  final SemanticTint tint;

  const _FlowChip(
      {required this.label, required this.amount, required this.tint});

  @override
  Widget build(BuildContext context) => TintCard(
        tint: tint,
        radius: Radii.small,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: AppType.currencyCode.copyWith(color: tint.body)),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatMoney(amount),
                  maxLines: 1,
                  softWrap: false,
                  style:
                      AppType.figureRow.copyWith(fontSize: 13, color: tint.ink)),
            ),
          ],
        ),
      );
}
