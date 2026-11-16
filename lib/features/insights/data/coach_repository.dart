import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/api_client.dart';
import '../../../core/finance/snapshot_provider.dart';
import '../../accounts/data/account_repository.dart';
import '../../planning/data/goal_repository.dart';
import '../../planning/data/obligation_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import '../domain/coach_message.dart';
import 'coach_service.dart';
import 'coach_tools.dart';

class CoachRepository {
  /// The thread to continue, creating one on first use.
  Future<String> currentThreadId() async {
    final res = await api.get('/coach/threads/current');
    return (res as Map)['id'] as String;
  }

  Future<String> startNewThread() async {
    final res = await api.post('/coach/threads');
    return (res as Map)['id'] as String;
  }

  Future<List<CoachMessage>> messages(String threadId) async {
    final rows = await api.get('/coach/threads/$threadId/messages');
    return (rows as List)
        .map((r) => CoachMessage.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Persists a turn in order, so replaying the thread reproduces exactly what
  /// the model saw. The backend stamps each row a strictly later created_at.
  Future<void> saveTurn(String threadId, List<PendingMessage> messages) async {
    if (messages.isEmpty) return;
    await api.post('/coach/threads/$threadId/messages', body: {
      'messages': [
        for (final m in messages)
          {
            'role': m.role.wire,
            'content': m.content,
            'tool_calls': m.toolCalls,
            'tool_call_id': m.toolCallId,
            'name': m.name,
            'actions': m.actions.isEmpty
                ? null
                : m.actions.map((a) => a.toJson()).toList(),
          },
      ],
    });
  }

  Future<void> clearThread(String threadId) async {
    await api.delete('/coach/threads/$threadId');
  }
}

final coachRepositoryProvider = Provider((_) => CoachRepository());

final coachThreadRefreshProvider = StateProvider<int>((_) => 0);

final coachThreadIdProvider = FutureProvider<String>((ref) async {
  ref.watch(coachThreadRefreshProvider);
  return ref.watch(coachRepositoryProvider).currentThreadId();
});

final coachMessagesProvider = FutureProvider<List<CoachMessage>>((ref) async {
  final threadId = await ref.watch(coachThreadIdProvider.future);
  return ref.watch(coachRepositoryProvider).messages(threadId);
});

void bumpCoachThread(WidgetRef ref) =>
    ref.read(coachThreadRefreshProvider.notifier).state++;

/// Everything the tools need to answer, gathered in one place so the coach and
/// the dashboard can never disagree.
final coachContextProvider = FutureProvider<CoachContext>((ref) async {
  final snapshot = await ref.watch(moneySnapshotProvider.future);
  final accounts = await ref.watch(accountsProvider.future);
  final txns = await ref.watch(transactionsProvider.future);
  final obligations = await ref.watch(obligationsProvider.future);
  final goals = await ref.watch(goalsProvider.future);

  return CoachContext(
    snapshot: snapshot,
    accounts: accounts.where((a) => !a.isArchived).toList(),
    txns: txns,
    obligations: obligations,
    goals: goals,
  );
});
