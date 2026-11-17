import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../domain/coach_action.dart';

class CoachException implements Exception {
  final String message;
  CoachException(this.message);
  @override
  String toString() => message;
}

/// One finished coach exchange.
class CoachAnswer {
  final String reply;
  final List<CoachAction> actions;
  final List<String> toolsUsed;

  const CoachAnswer({
    required this.reply,
    required this.actions,
    required this.toolsUsed,
  });
}

/// The coach lives on the server: it holds the Anthropic key, runs the whole
/// tool loop against the user's data and returns the finished answer. The app
/// sends a question and renders what comes back.
class ServerCoachTransport {
  final ApiClient client;

  ServerCoachTransport({ApiClient? client}) : client = client ?? api;

  Future<CoachAnswer> ask({
    required String threadId,
    required String question,
  }) async {
    final dynamic data;
    try {
      data = await client.post('/coach/ask', body: {
        'thread_id': threadId,
        'question': question,
      });
    } on ApiException catch (e) {
      throw CoachException(e.message);
    }

    if (data is! Map) {
      throw CoachException('The coach returned an unexpected response.');
    }
    final m = Map<String, dynamic>.from(data);

    final actions = ((m['actions'] as List?) ?? const [])
        .whereType<Map>()
        .map((a) => CoachAction.fromJson(Map<String, dynamic>.from(a)))
        .whereType<CoachAction>()
        .toList();

    return CoachAnswer(
      reply: m['reply'] as String? ?? '',
      actions: actions,
      toolsUsed: [
        for (final t in (m['tools_used'] as List?) ?? const []) t.toString(),
      ],
    );
  }
}

/// The transport the app should use right now.
final serverCoachTransportProvider =
    Provider<ServerCoachTransport>((_) => ServerCoachTransport());
