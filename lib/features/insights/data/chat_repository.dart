import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/supabase_client.dart';
import '../domain/chat_message.dart';

class ChatRepository {
  Future<List<ChatMessage>> list({int limit = 50}) async {
    final rows = await supabase
        .from('ai_chats')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => ChatMessage.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> create({
    required String question,
    required String answer,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('ai_chats')
        .insert({
          'user_id': userId,
          'question': question,
          'answer': answer,
        })
        .select()
        .single();
    return ChatMessage.fromJson(row);
  }

  Future<void> delete(String id) async {
    await supabase.from('ai_chats').delete().eq('id', id);
  }

  Future<void> clearAll() async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('ai_chats').delete().eq('user_id', userId);
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
