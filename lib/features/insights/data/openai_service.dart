import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/finance/money_engine.dart';
import '../../../core/formatters.dart';
import '../../accounts/domain/account.dart';
import '../../planning/domain/goal.dart';
import '../../planning/domain/obligation.dart';
import '../../transactions/domain/transaction.dart';

class OpenAIException implements Exception {
  final String message;
  OpenAIException(this.message);
  @override
  String toString() => message;
}

class OpenAIService {
  final String apiKey;
  final String model;
  OpenAIService({required this.apiKey, this.model = 'gpt-4o-mini'});

  Future<List<String>> tipBatch({
    required int count,
    required List<Account> accounts,
    required List<Txn> txns,
    List<Obligation> obligations = const [],
    List<Goal> goals = const [],
  }) async {
    if (apiKey.isEmpty) throw OpenAIException('No API key.');
    final context =
        _buildContext(accounts, txns, obligations: obligations, goals: goals);
    final hasData = txns.isNotEmpty;
    final prompt = hasData
        ? 'Generate $count distinct, short personal-finance tips for this user. '
            'Each tip: 2 sentences max, 50 words max, plain text, no markdown, no greeting. '
            'Reference real numbers from their data (in GHS) where useful. Each tip must '
            'cover a different angle (e.g. spending category, savings, emergency fund, '
            'budgeting habit, mindset).\n\nReturn ONLY the tips, one per line, prefixed '
            'with "1." through "$count." (e.g. "1. ..."). No extra commentary.\n\nContext:\n$context'
        : 'Generate $count distinct short personal-finance tips for a beginner with no '
            'transactions yet. Each tip: 2 sentences max, 50 words max, plain text, no '
            'markdown, no greeting. Topics should vary (e.g. tracking habit, saving, '
            'budgeting, debt, mindset).\n\nReturn ONLY the tips, one per line, prefixed '
            'with "1." through "$count." (e.g. "1. ...").';
    final raw = await _chat(
      systemPrompt:
          'You are a concise personal-finance coach for a user in Ghana (currency GHS). '
              'Output plain text only. No markdown.',
      userPrompt: prompt,
      maxTokens: 800,
      temperature: 0.85,
    );
    final tips = <String>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final m = RegExp(r'^\d+[\.\)]\s*(.+)$').firstMatch(trimmed);
      if (m != null) {
        tips.add(m.group(1)!.trim());
      } else if (tips.isNotEmpty) {
        // continuation of previous bullet
        tips[tips.length - 1] = '${tips.last} $trimmed';
      }
    }
    if (tips.isEmpty) {
      throw OpenAIException('Could not parse tip list from response.');
    }
    return tips;
  }

  Future<String> dailyTip({
    required List<Account> accounts,
    required List<Txn> txns,
    List<Obligation> obligations = const [],
    List<Goal> goals = const [],
  }) async {
    if (apiKey.isEmpty) throw OpenAIException('No API key.');
    final context =
        _buildContext(accounts, txns, obligations: obligations, goals: goals);
    final hasData = txns.isNotEmpty;
    final userPrompt = hasData
        ? 'Generate ONE short, specific finance tip personalised to this user. '
            'Use a concrete number from their data (in GHS). 2–3 sentences max. '
            'Friendly tone, no greeting, no sign-off, no markdown headers.\n\nContext:\n$context'
        : 'The user has no transactions yet. Give one short, encouraging '
            'personal-finance tip (any topic, 2 sentences max) to motivate them '
            'to start logging. No greeting, no sign-off, no markdown.';
    return _chat(
      systemPrompt:
          'You are a concise personal-finance coach for a user in Ghana (currency GHS). '
              'Output plain text only, never markdown. Maximum 60 words.',
      userPrompt: userPrompt,
      maxTokens: 180,
      temperature: 0.8,
    );
  }

  Future<String> ask({
    required String question,
    required List<Account> accounts,
    required List<Txn> txns,
    List<Obligation> obligations = const [],
    List<Goal> goals = const [],
  }) async {
    if (apiKey.isEmpty) {
      throw OpenAIException('Add your OpenAI API key in settings.');
    }
    final context =
        _buildContext(accounts, txns, obligations: obligations, goals: goals);
    return _chat(
      systemPrompt:
          'You are a friendly, concrete personal finance coach for a user in Ghana '
              '(currency GHS). Use the JSON context they provide to give specific, '
              'actionable advice. Keep answers under 250 words. Use short paragraphs '
              'and bullet points where useful. Never invent numbers — if the data is '
              'missing, say so and suggest what to log.\n\n'
              'Every figure you need is already computed in the context — never do '
              'your own arithmetic on it. When asked which account to pay from, '
              'reason from free_to_move, keep_at_least, bills_pinned_here and each '
              'account\'s purpose, name the account outright, and say what you are '
              'protecting by not using the others.',
      userPrompt: 'Context:\n$context\n\nQuestion: $question',
      maxTokens: 700,
      temperature: 0.6,
    );
  }

  Future<String> _chat({
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
    required double temperature,
  }) async {
    final body = jsonEncode({
      'model': model,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    });

    final res = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (res.statusCode != 200) {
      String msg = 'OpenAI error (${res.statusCode})';
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final err = j['error'];
        if (err is Map && err['message'] is String) msg = err['message'] as String;
      } catch (_) {}
      throw OpenAIException(msg);
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = j['choices'] as List;
    if (choices.isEmpty) throw OpenAIException('Empty response.');
    final msg = (choices.first as Map)['message'] as Map;
    return (msg['content'] as String).trim();
  }

  /// Everything the coach is allowed to know, with every figure already
  /// computed.
  ///
  /// The model is never asked to do arithmetic — safe-to-spend, runway and
  /// category movement come from [buildSnapshot], so the advice is grounded in
  /// numbers that were tested rather than numbers that were guessed.
  String _buildContext(
    List<Account> accounts,
    List<Txn> txns, {
    List<Obligation> obligations = const [],
    List<Goal> goals = const [],
  }) {
    final s = buildSnapshot(
      accounts: accounts,
      txns: txns,
      obligations: obligations,
      goals: goals,
    );

    final recent = txns.where((t) => t.isRealMoneyMovement).take(10).map((t) => {
          'date': dateFmt.format(t.date),
          'type': t.type.label,
          'amount': t.amount,
          'category': t.category,
          if (t.description != null && t.description!.isNotEmpty)
            'note': t.description,
        }).toList();

    final ctx = {
      'currency': 'GHS',
      'today': dateFmt.format(s.asOf),
      'position': {
        'total_balance': s.totalBalance,
        'spendable_now': s.liquid,
        'reserved': s.reserved,
        'locked': s.locked,
        'minimum_balances_held': s.floors,
        'held_for_goals': s.goalReserve,
        'bills_due_before_${dateFmt.format(s.horizon)}': s.committed,
        // The single number that answers "can I afford this?".
        'safe_to_spend': s.safeToSpend,
      },
      'pace': {
        'average_spend_per_day': s.dailyBurn,
        'days_of_cash_left': s.runwayDays,
        'days_until_next_income': s.daysUntilIncome,
        'will_run_short_before_income': s.willFallShort,
        if (s.willFallShort) 'short_by_days': s.shortfallDays,
      },
      'accounts': [
        for (final st in s.standings)
          {
            'name': st.account.name,
            'kind': st.account.kind.label,
            'liquidity': st.account.liquidity.label,
            'balance': st.account.balance,
            'keep_at_least': st.account.minBalance,
            'free_to_move': st.freeToMove,
            'bills_pinned_here': st.committed,
            if (st.account.purpose != null) 'purpose': st.account.purpose,
            if (st.isBelowFloor) 'warning': 'below its minimum balance',
          },
      ],
      'upcoming': [
        for (final o in obligations.where((o) => o.isActive))
          {
            'name': o.name,
            'direction': o.isOutflow ? 'bill' : 'income',
            'amount': o.amount,
            'every': o.cadence.label,
            'next': dateFmt.format(o.nextDue),
          },
      ],
      'goals': [
        for (final g in goals.where((g) => g.isActive))
          {
            'name': g.name,
            'target': g.targetAmount,
            'set_aside': g.savedAmount,
            if (g.targetDate != null) 'by': dateFmt.format(g.targetDate!),
          },
      ],
      'last_30_days': {
        'income': s.income30d,
        'spending': s.spend30d,
        'net': s.income30d - s.spend30d,
      },
      // Includes movement against the previous 30 days, so the coach can say
      // what changed rather than only what happened.
      'spending_by_category_30d': [
        for (final c in s.categories.take(8))
          {
            'category': c.category,
            'amount': c.amount,
            'previous_30d': c.previousAmount,
            if (c.changeRatio != null)
              'change_pct': (c.changeRatio! * 100).round(),
          },
      ],
      'recent_transactions': recent,
    };
    return const JsonEncoder.withIndent('  ').convert(ctx);
  }
}
