import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/accounts/data/account_repository.dart';
import '../../features/planning/data/goal_repository.dart';
import '../../features/planning/data/obligation_repository.dart';
import '../../features/transactions/data/transaction_repository.dart';
import 'alerts.dart';
import 'money_engine.dart';

/// The one place the app's understanding of the user's money lives.
///
/// The dashboard, the coach and any future advice all read from this, so they
/// can never disagree about the numbers.
final moneySnapshotProvider = FutureProvider<MoneySnapshot>((ref) async {
  final accounts = await ref.watch(accountsProvider.future);
  final txns = await ref.watch(transactionsProvider.future);
  final obligations = await ref.watch(obligationsProvider.future);
  final goals = await ref.watch(goalsProvider.future);

  return buildSnapshot(
    accounts: accounts,
    txns: txns,
    obligations: obligations,
    goals: goals,
  );
});

/// What the app wants to say to the user right now, worst first.
final moneyAlertsProvider = FutureProvider<List<MoneyAlert>>((ref) async {
  final snapshot = await ref.watch(moneySnapshotProvider.future);
  final obligations = await ref.watch(obligationsProvider.future);
  final goals = await ref.watch(goalsProvider.future);

  return buildAlerts(
    snapshot: snapshot,
    obligations: obligations,
    goals: goals,
  );
});
