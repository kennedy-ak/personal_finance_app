import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/formatters.dart';
import '../../accounts/domain/account.dart';
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
  }) async {
    if (apiKey.isEmpty) throw OpenAIException('No API key.');
    final context = _buildContext(accounts, txns);
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
  }) async {
    if (apiKey.isEmpty) throw OpenAIException('No API key.');
    final context = _buildContext(accounts, txns);
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
  }) async {
    if (apiKey.isEmpty) {
      throw OpenAIException('Add your OpenAI API key in settings.');
    }
    final context = _buildContext(accounts, txns);
    return _chat(
      systemPrompt:
          'You are a friendly, concrete personal finance coach for a user in Ghana '
              '(currency GHS). Use the JSON context they provide to give specific, '
              'actionable advice. Keep answers under 250 words. Use short paragraphs '
              'and bullet points where useful. Never invent numbers — if the data is '
              'missing, say so and suggest what to log.',
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

  String _buildContext(List<Account> accounts, List<Txn> txns) {
    final totalBal = accounts.fold<double>(0, (s, a) => s + a.balance);
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final recent = txns.where((t) => !t.date.isBefore(cutoff)).toList();
    final inc = recent.where((t) => t.type == TxnType.income).fold<double>(0, (s, t) => s + t.amount);
    final exp = recent.where((t) => t.type == TxnType.expense).fold<double>(0, (s, t) => s + t.amount);

    final byCat = <String, double>{};
    for (final t in recent.where((t) => t.type == TxnType.expense)) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final last10 = txns.take(10).map((t) => {
          'date': dateFmt.format(t.date),
          'type': t.type.label,
          'amount': t.amount,
          'category': t.category,
          if (t.description != null && t.description!.isNotEmpty)
            'note': t.description,
        }).toList();

    final ctx = {
      'currency': 'GHS',
      'today': dateFmt.format(DateTime.now()),
      'total_balance': totalBal,
      'accounts': accounts
          .map((a) => {'name': a.name, 'balance': a.balance})
          .toList(),
      'last_30_days': {
        'income': inc,
        'expense': exp,
        'net': inc - exp,
        'transaction_count': recent.length,
      },
      'top_categories_30d': [
        for (final c in cats.take(8)) {'category': c.key, 'amount': c.value},
      ],
      'recent_transactions': last10,
    };
    return const JsonEncoder.withIndent('  ').convert(ctx);
  }
}
