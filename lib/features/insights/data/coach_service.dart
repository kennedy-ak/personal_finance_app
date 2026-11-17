import '../domain/coach_action.dart';
import 'coach_transport.dart';

/// Everything produced by one exchange.
class CoachTurn {
  /// The coach's final words.
  final String reply;

  /// Proposals to show as cards. Applying one is the user's tap, never the
  /// coach's.
  final List<CoachAction> actions;

  /// Names of tools the server ran, in order — surfaced so the user can see
  /// the coach actually looked things up.
  final List<String> toolsUsed;

  const CoachTurn({
    required this.reply,
    required this.actions,
    required this.toolsUsed,
  });
}

/// How a question reaches the server. ServerCoachTransport.ask satisfies this;
/// tests substitute their own.
typedef CoachAsk = Future<CoachAnswer> Function({
  required String threadId,
  required String question,
});

/// One question, one finished answer. The server owns the loop, the tools and
/// the memory — it saves the turn before answering.
class CoachService {
  final CoachAsk ask;

  CoachService({required this.ask});

  Future<CoachTurn> send({
    required String question,
    required String threadId,
  }) async {
    final answer = await ask(threadId: threadId, question: question);
    final reply = answer.reply.trim().isNotEmpty
        ? answer.reply
        : 'I could not put an answer together for that one. Try asking a '
            'different way.';
    return CoachTurn(
      reply: reply,
      actions: answer.actions,
      toolsUsed: answer.toolsUsed,
    );
  }
}
