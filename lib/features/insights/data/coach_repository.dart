import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/api_client.dart';
import '../domain/coach_message.dart';

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
