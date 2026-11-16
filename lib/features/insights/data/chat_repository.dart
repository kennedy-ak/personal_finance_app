import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/api_client.dart';
import '../domain/chat_message.dart';

class ChatRepository {
  Future<List<ChatMessage>> list({int limit = 50}) async {
    final rows = await api.get('/coach/chats', query: {'limit': '$limit'});
    return (rows as List)
        .map((r) => ChatMessage.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> create({
    required String question,
    required String answer,
  }) async {
    final row = await api.post('/coach/chats', body: {
      'question': question,
      'answer': answer,
    });
    return ChatMessage.fromJson(row as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await api.delete('/coach/chats/$id');
  }

  Future<void> clearAll() async {
    await api.delete('/coach/chats');
  }
}

final chatRepositoryProvider = Provider((_) => ChatRepository());

final chatRefreshProvider = StateProvider<int>((_) => 0);

final chatHistoryProvider = FutureProvider<List<ChatMessage>>((ref) async {
  ref.watch(chatRefreshProvider);
  return ref.read(chatRepositoryProvider).list();
});

void bumpChats(WidgetRef ref) =>
    ref.read(chatRefreshProvider.notifier).state++;
