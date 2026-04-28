import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/kpi_card.dart';
import '../../../shared/widgets/section_header.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import 'ask_ai_tab.dart';
import 'daily_tip_card.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final txnsAsync = ref.watch(transactionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.insights), text: 'Overview'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'Ask AI'),
          ],
        ),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (accounts) => txnsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (txns) => TabBarView(
            controller: _tab,
            children: [
              _Body(accounts: accounts, txns: txns),
              AskAiTab(accounts: accounts, txns: txns),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final List<Account> accounts;
  final List<Txn> txns;
  const _Body({required this.accounts, required this.txns});

  @override
  Widget build(BuildContext context) {
    final totalBalance = accounts.fold<double>(0, (s, a) => s + a.balance);
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final recent = txns.where((t) => !t.date.isBefore(cutoff));
    final income30 =
        recent.where((t) => t.type == TxnType.income).fold<double>(0, (s, t) => s + t.amount);
    final expense30 =
        recent.where((t) => t.type == TxnType.expense).fold<double>(0, (s, t) => s + t.amount);
    final net30 = income30 - expense30;
    final dailyExp = expense30 / 30;
    final projectedMonthlyExp = dailyExp * 30;
    final emergencyMonths =
        projectedMonthlyExp > 0 ? totalBalance / projectedMonthlyExp : 0.0;
    final savingsRate = income30 > 0 ? (income30 - expense30) / income30 * 100 : 0.0;

    final byCat = <String, double>{};
    for (final t in recent.where((t) => t.type == TxnType.expense)) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }
    final topCats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topCat = topCats.isNotEmpty ? topCats.first : null;
    final topPct = topCat != null && expense30 > 0 ? topCat.value / expense30 * 100 : 0.0;

    final score = _healthScore(
      hasTxns: txns.isNotEmpty,
      net: net30,
      savingsRate: savingsRate,
      emergencyMonths: emergencyMonths,
      topConcentration: topPct,
      hasAccounts: accounts.isNotEmpty,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _HealthScoreCard(score: score, hasData: txns.isNotEmpty),
        const SizedBox(height: 14),
        const DailyTipCard(),
        const SizedBox(height: 18),
        if (txns.isEmpty) ...[
          _GettingStartedCard(hasAccounts: accounts.isNotEmpty),
          const SizedBox(height: 22),
        ] else ...[
          const SectionHeader(title: 'Your numbers'),
          Row(
            children: [
              Expanded(
                child: KpiCard(
                  label: 'Savings rate',
                  value: '${savingsRate.toStringAsFixed(0)}%',
                  sub: 'last 30 days',
                  icon: Icons.savings,
                  gradient: const [AppColors.incomeGradStart, AppColors.incomeGradEnd],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: KpiCard(
                  label: 'Emergency',
                  value: '${emergencyMonths.toStringAsFixed(1)} mo',
                  sub: 'covered',
                  icon: Icons.shield,
                  gradient: const [AppColors.netGradStart, AppColors.netGradEnd],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: KpiCard(
                  label: 'Daily avg expense',
                  value: formatMoney(dailyExp),
                  icon: Icons.calendar_today,
                  gradient: const [AppColors.expenseGradStart, AppColors.expenseGradEnd],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: KpiCard(
                  label: 'Monthly projection',
                  value: formatMoney(projectedMonthlyExp),
                  icon: Icons.event_repeat,
                  gradient: const [Color(0xFF374151), Color(0xFF6B7280)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const SectionHeader(title: 'Recommendations'),
          ..._buildTips(
            net30: net30,
            emergencyMonths: emergencyMonths,
            projectedExp: projectedMonthlyExp,
            topCat: topCat,
            topPct: topPct,
            lowAccounts: accounts.where((a) => a.balance < 100).toList(),
          ).map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TipCard(tip: t),
              )),
          const SizedBox(height: 6),
        ],
        const SectionHeader(title: 'Financial wellness'),
        for (final l in _wellnessLessons)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LessonCard(lesson: l),
          ),
        const SizedBox(height: 14),
        Card(
          color: AppColors.seed.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: AppColors.seed.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: AppColors.seed),
                    SizedBox(width: 8),
                    Text('Personalised coach',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'The more you log, the smarter your insights get. Try to record every '
                  'expense for one week — patterns will appear automatically here.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.seed,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () => context.push('/add'),
                  icon: const Icon(Icons.add),
                  label: const Text('Log a transaction'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<_Tip> _buildTips({
    required double net30,
    required double emergencyMonths,
    required double projectedExp,
    required MapEntry<String, double>? topCat,
    required double topPct,
    required List<Account> lowAccounts,
  }) {
    final tips = <_Tip>[];
    if (net30 > 0) {
      tips.add(_Tip(
        icon: Icons.trending_up,
        color: AppColors.income,
        title: 'Healthy cash flow',
        body:
            'You earned ${formatMoney(net30)} more than you spent in the last 30 days. Move part of it into savings.',
      ));
    } else if (net30 < 0) {
      tips.add(_Tip(
        icon: Icons.warning_amber,
        color: AppColors.expense,
        title: 'Spending exceeds income',
        body:
            'You spent ${formatMoney(net30.abs())} more than you earned. Review your top categories.',
      ));
    }
    if (emergencyMonths >= 3) {
      tips.add(_Tip(
        icon: Icons.shield,
        color: AppColors.income,
        title: 'Strong emergency buffer',
        body:
            'Your balance covers ~${emergencyMonths.toStringAsFixed(1)} months. Push toward 6+ months for full safety.',
      ));
    } else if (projectedExp > 0) {
      tips.add(_Tip(
        icon: Icons.savings_outlined,
        color: AppColors.warning,
        title: 'Build an emergency fund',
        body:
            'Your balance covers only ~${emergencyMonths.toStringAsFixed(1)} months. Target 3–6 months of expenses.',
      ));
    }
    if (topCat != null && topPct > 40) {
      tips.add(_Tip(
        icon: Icons.pie_chart_outline,
        color: AppColors.warning,
        title: 'Concentrated spending',
        body:
            '${topPct.toStringAsFixed(0)}% of expenses went to ${topCat.key}. Consider a budget cap.',
      ));
    } else if (topCat != null) {
      tips.add(_Tip(
        icon: Icons.category,
        color: AppColors.seed,
        title: 'Top category: ${topCat.key}',
        body:
            '${formatMoney(topCat.value)} (${topPct.toStringAsFixed(0)}% of last-30-day expenses).',
      ));
    }
    for (final a in lowAccounts) {
      tips.add(_Tip(
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.warning,
        title: 'Low balance: ${a.name}',
        body: 'Currently ${formatMoney(a.balance)}.',
      ));
    }
    return tips;
  }

  static int _healthScore({
    required bool hasTxns,
    required bool hasAccounts,
    required double net,
    required double savingsRate,
    required double emergencyMonths,
    required double topConcentration,
  }) {
    if (!hasTxns) return hasAccounts ? 25 : 5;
    var s = 50.0;
    s += net >= 0 ? 10 : -10;
    if (savingsRate >= 20) s += 15; else if (savingsRate >= 10) s += 8; else if (savingsRate < 0) s -= 10;
    if (emergencyMonths >= 6) s += 15; else if (emergencyMonths >= 3) s += 8; else if (emergencyMonths < 1) s -= 8;
    if (topConcentration > 50) s -= 8; else if (topConcentration > 0 && topConcentration < 35) s += 5;
    return s.clamp(0, 100).round();
  }
}

class _HealthScoreCard extends StatelessWidget {
  final int score;
  final bool hasData;
  const _HealthScoreCard({required this.score, required this.hasData});

  @override
  Widget build(BuildContext context) {
    final color = score >= 70
        ? AppColors.income
        : score >= 40
            ? AppColors.warning
            : AppColors.expense;
    final label = !hasData
        ? 'Start logging'
        : score >= 70
            ? 'Excellent'
            : score >= 40
                ? 'Doing OK'
                : 'Needs work';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [AppColors.gradStart, AppColors.gradEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.gradEnd.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: _ScoreRing(score: score, ringColor: color),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Financial health',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text(label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    )),
                const SizedBox(height: 6),
                Text(
                  hasData
                      ? 'Based on cash flow, savings rate, and emergency buffer.'
                      : 'Add transactions to see your personalised score.',
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final int score;
  final Color ringColor;
  const _ScoreRing({required this.score, required this.ringColor});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingPainter(score: score, ringColor: Colors.white),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$score',
                style: const TextStyle(
                    color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
            const Text('/100',
                style: TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int score;
  final Color ringColor;
  _RingPainter({required this.score, required this.ringColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = ringColor
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    final sweep = (score / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.score != score || oldDelegate.ringColor != ringColor;
}

class _GettingStartedCard extends StatelessWidget {
  final bool hasAccounts;
  const _GettingStartedCard({required this.hasAccounts});

  @override
  Widget build(BuildContext context) {
    final steps = [
      _Step(
        done: hasAccounts,
        title: 'Set up an account',
        body: 'Add your bank, mobile money or cash wallets.',
        icon: Icons.account_balance_wallet,
        cta: 'Manage accounts',
        route: '/accounts',
      ),
      _Step(
        done: false,
        title: 'Log your first transaction',
        body: 'Start with today\'s coffee or your last paycheque.',
        icon: Icons.add_circle,
        cta: 'Add transaction',
        route: '/add',
      ),
      _Step(
        done: false,
        title: 'Build a 7-day habit',
        body: 'Record every expense for one week to unlock real insights.',
        icon: Icons.event_available,
        cta: null,
        route: null,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Getting started',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('A 60-second setup unlocks your dashboard.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            for (var i = 0; i < steps.length; i++) ...[
              _StepRow(step: steps[i], number: i + 1),
              if (i < steps.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _Step {
  final bool done;
  final String title;
  final String body;
  final IconData icon;
  final String? cta;
  final String? route;
  const _Step({
    required this.done,
    required this.title,
    required this.body,
    required this.icon,
    required this.cta,
    required this.route,
  });
}

class _StepRow extends StatelessWidget {
  final _Step step;
  final int number;
  const _StepRow({required this.step, required this.number});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: step.done ? AppColors.income : cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            step.done ? Icons.check : step.icon,
            color: step.done ? Colors.white : cs.primary,
            size: 17,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(step.body,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35)),
              if (step.cta != null && !step.done) ...[
                const SizedBox(height: 6),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => context.push(step.route!),
                  child: Text(step.cta!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Tip {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Tip({required this.icon, required this.color, required this.title, required this.body});
}

class _TipCard extends StatelessWidget {
  final _Tip tip;
  const _TipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tip.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tip.icon, color: tip.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tip.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(tip.body,
                      style: const TextStyle(fontSize: 12.5, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lesson {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Lesson(this.icon, this.color, this.title, this.body);
}

const _wellnessLessons = <_Lesson>[
  _Lesson(
    Icons.balance,
    AppColors.accent,
    '50 / 30 / 20 rule',
    '50% of income to needs, 30% to wants, 20% to savings & debt repayment.',
  ),
  _Lesson(
    Icons.shield,
    AppColors.seed,
    'Emergency fund first',
    'Aim to set aside 3–6 months of expenses before chasing investments.',
  ),
  _Lesson(
    Icons.auto_graph,
    AppColors.income,
    'Pay yourself first',
    'Automate a transfer to savings the day your salary lands — what you don\'t see, you don\'t spend.',
  ),
  _Lesson(
    Icons.local_offer_outlined,
    AppColors.warning,
    'Watch the silent killers',
    'Subscriptions, delivery fees and small daily treats often add up to more than your rent.',
  ),
  _Lesson(
    Icons.trending_up,
    AppColors.netGradStart,
    'Start investing early',
    'Even a small recurring contribution compounds dramatically over a decade.',
  ),
];

class _LessonCard extends StatelessWidget {
  final _Lesson lesson;
  const _LessonCard({required this.lesson});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: lesson.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(lesson.icon, color: lesson.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(lesson.body,
                      style: const TextStyle(fontSize: 12.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
