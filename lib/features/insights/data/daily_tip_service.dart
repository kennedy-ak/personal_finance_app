import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/formatters.dart';
import '../../../core/notifications.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../planning/data/goal_repository.dart';
import '../../planning/data/obligation_repository.dart';
import '../../planning/domain/goal.dart';
import '../../planning/domain/obligation.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import 'api_key_store.dart';
import 'openai_service.dart';

const _kBatchTips = 'tip_batch_tips';
const _kBatchStart = 'tip_batch_start_date';
const tipBatchSize = 5;

class TipBatch {
  final List<String> tips;
  final DateTime startDate;
  const TipBatch({required this.tips, required this.startDate});

  /// Returns the tip for today, or null if today is past the batch window.
  String? tipForToday() {
    final today = DateTime.now();
    final t0 = DateTime(startDate.year, startDate.month, startDate.day);
    final t1 = DateTime(today.year, today.month, today.day);
    final diff = t1.difference(t0).inDays;
    if (diff < 0 || diff >= tips.length) return null;
    return tips[diff];
  }

  bool get isExpired => tipForToday() == null;
}

class DailyTipService {
  Future<TipBatch?> cachedBatch() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kBatchTips);
    final dateStr = p.getString(_kBatchStart);
    if (raw == null || dateStr == null) return null;
    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      return TipBatch(tips: list, startDate: DateTime.parse(dateStr));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveBatch(TipBatch b) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBatchTips, jsonEncode(b.tips));
    await p.setString(_kBatchStart, dateFmt.format(b.startDate));
  }

  Future<TipBatch> generateBatch({
    required String apiKey,
    required String model,
    required List<Account> accounts,
    required List<Txn> txns,
    List<Obligation> obligations = const [],
    List<Goal> goals = const [],
  }) async {
    final svc = OpenAIService(apiKey: apiKey, model: model);
    final tips = await svc.tipBatch(
      count: tipBatchSize,
      accounts: accounts,
      txns: txns,
      obligations: obligations,
      goals: goals,
    );
    final batch = TipBatch(tips: tips, startDate: DateTime.now());
    await _saveBatch(batch);
    return batch;
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kBatchTips);
    await p.remove(_kBatchStart);
  }
}

final dailyTipServiceProvider = Provider((_) => DailyTipService());

final dailyTipRefreshProvider = StateProvider<int>((_) => 0);

/// Returns today's tip — uses the cached 5-tip batch if still valid; otherwise
/// fetches a fresh batch in the background. Schedules notifications too.
final dailyTipProvider = FutureProvider<String?>((ref) async {
  ref.watch(dailyTipRefreshProvider);
  final svc = ref.read(dailyTipServiceProvider);
  final keyStore = ref.read(apiKeyStoreProvider);
  final key = await keyStore.getKey();
  if (key == null || key.isEmpty) return null;

  final cached = await svc.cachedBatch();
  TipBatch batch;
  if (cached != null && !cached.isExpired) {
    batch = cached;
  } else {
    final accounts = await ref.read(accountsProvider.future);
    final txns = await ref.read(transactionsProvider.future);
    final obligations = await ref.read(obligationsProvider.future);
    final goals = await ref.read(goalsProvider.future);
    final model = await keyStore.getModel();
    batch = await svc.generateBatch(
      apiKey: key,
      model: model,
      accounts: accounts,
      txns: txns,
      obligations: obligations,
      goals: goals,
    );
    final tipNotif = await ref.read(tipNotifStoreProvider).load();
    if (tipNotif.enabled) {
      final notif = ref.read(notificationServiceProvider);
      await notif.scheduleTipBatch(
        hour: tipNotif.hour, minute: tipNotif.minute, tips: batch.tips);
    }
  }
  return batch.tipForToday();
});
