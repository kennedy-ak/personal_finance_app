import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/formatters.dart';
import '../../../core/supabase_client.dart';
import '../domain/goal.dart';

class GoalRepository {
  Future<List<Goal>> list() async {
    final rows = await supabase
        .from('goals')
        .select()
        .order('priority')
        .order('created_at');
    return (rows as List).map((r) => Goal.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Goal> create({
    required String name,
    required double targetAmount,
    double savedAmount = 0,
    DateTime? targetDate,
    String? accountId,
    int priority = 0,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('goals')
        .insert({
          'user_id': userId,
          'name': name,
          'target_amount': targetAmount,
          'saved_amount': savedAmount,
          'target_date': targetDate == null ? null : dateFmt.format(targetDate),
          'account_id': accountId,
          'priority': priority,
        })
        .select()
        .single();
    return Goal.fromJson(row);
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
    await supabase.from('goals').update(patch).eq('id', id);
  }

  /// Adds to (or subtracts from) what has been set aside, never below zero.
  Future<void> contribute(Goal goal, double delta) async {
    final next = goal.savedAmount + delta;
    await update(goal.id, savedAmount: next < 0 ? 0 : next);
  }

  Future<void> delete(String id) async {
    await supabase.from('goals').delete().eq('id', id);
  }
}

final goalRepositoryProvider = Provider((_) => GoalRepository());

final goalsRefreshProvider = StateProvider<int>((_) => 0);

final goalsProvider = FutureProvider<List<Goal>>((ref) async {
  ref.watch(goalsRefreshProvider);
  return ref.watch(goalRepositoryProvider).list();
});

void bumpGoals(WidgetRef ref) => ref.read(goalsRefreshProvider.notifier).state++;
