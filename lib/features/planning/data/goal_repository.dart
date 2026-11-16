import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/api_client.dart';
import '../../../core/formatters.dart';
import '../domain/goal.dart';

class GoalRepository {
  Future<List<Goal>> list() async {
    final rows = await api.get('/goals');
    return (rows as List)
        .map((r) => Goal.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Goal> create({
    required String name,
    required double targetAmount,
    double savedAmount = 0,
    DateTime? targetDate,
    String? accountId,
    int priority = 0,
  }) async {
    final row = await api.post('/goals', body: {
      'name': name,
      'target_amount': targetAmount,
      'saved_amount': savedAmount,
      'target_date': targetDate == null ? null : dateFmt.format(targetDate),
      'account_id': accountId,
      'priority': priority,
    });
    return Goal.fromJson(row as Map<String, dynamic>);
  }

  Future<void> update(
    String id, {
    String? name,
    double? targetAmount,
    double? savedAmount,
    DateTime? targetDate,
    bool clearTargetDate = false,
    String? accountId,
    int? priority,
    bool? isActive,
  }) async {
    final patch = <String, dynamic>{
      'name': ?name,
      'target_amount': ?targetAmount,
      'saved_amount': ?savedAmount,
      if (clearTargetDate)
        'target_date': null
      else if (targetDate != null)
        'target_date': dateFmt.format(targetDate),
      if (accountId != null) 'account_id': accountId.isEmpty ? null : accountId,
      'priority': ?priority,
      'is_active': ?isActive,
    };
    if (patch.isEmpty) return;
    await api.patch('/goals/$id', body: patch);
  }

  /// Adds to (or subtracts from) what has been set aside, never below zero.
  Future<void> contribute(Goal goal, double delta) async {
    final next = goal.savedAmount + delta;
    await update(goal.id, savedAmount: next < 0 ? 0 : next);
  }

  Future<void> delete(String id) async {
    await api.delete('/goals/$id');
  }
}

final goalRepositoryProvider = Provider((_) => GoalRepository());

final goalsRefreshProvider = StateProvider<int>((_) => 0);

final goalsProvider = FutureProvider<List<Goal>>((ref) async {
  ref.watch(goalsRefreshProvider);
  return ref.watch(goalRepositoryProvider).list();
});

void bumpGoals(WidgetRef ref) => ref.read(goalsRefreshProvider.notifier).state++;
