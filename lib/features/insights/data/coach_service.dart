import 'dart:convert';

import '../../../core/formatters.dart';
import '../domain/coach_action.dart';
import '../domain/coach_message.dart';
import 'coach_tools.dart';
import 'coach_transport.dart';

/// Everything produced by one exchange: the bookkeeping the model needs next
/// time, and the actions being offered to the user.
class CoachTurn {
  /// New messages in order, ready to persist. Includes tool-call and tool-result
  /// rows, not just the visible reply.
  final List<PendingMessage> messages;

  /// The coach's final words.
  final String reply;

  /// Proposals gathered along the way.
  final List<CoachAction> actions;

  /// Names of tools that ran, in order — surfaced in the UI so the user can see
  /// the coach actually looked things up.
  final List<String> toolsUsed;

  const CoachTurn({
    required this.messages,
    required this.reply,
    required this.actions,
    required this.toolsUsed,
  });
}

/// A message the service produced but has not yet written to the database.
class PendingMessage {
  final CoachRole role;
  final String? content;
  final List<Map<String, dynamic>>? toolCalls;
  final String? toolCallId;
  final String? name;
  final List<CoachAction> actions;

  const PendingMessage({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
    this.name,
    this.actions = const [],
  });
}

/// How many rounds of tool calls to allow before insisting on an answer.
///
/// Deep enough for "check the position, then plan a payment, then offer the
/// transfer", shallow enough that a confused model cannot loop forever on the
/// user's money.
const int kMaxToolRounds = 5;

/// How many past messages to replay. Old enough to remember the conversation,
/// short enough to stay affordable.
const int kHistoryWindow = 24;

/// Turns a stored thread into a message list the provider will accept.
///
/// A thread is not a flat list of prose. An assistant turn that called tools is
/// followed by one `tool` row per call, and the provider rejects the whole
/// request if that pairing is broken:
///
///   messages with role 'tool' must be a response to a preceeding message
///   with 'tool_calls'
///
/// Two things break it. Trimming to the last N rows lands mid-group and leaves
/// the replay opening on orphaned tool results. And a turn that failed to save
/// completely leaves a group in the database that can never be completed.
/// Neither is recoverable at the provider, so the pairing is enforced here
/// instead: a group is replayed only when every call it made has a matching
/// result, and anything else is reduced to the prose the model actually said.
List<Map<String, dynamic>> replayHistory(List<CoachMessage> history) {
  final windowed = _window(history);
  final out = <Map<String, dynamic>>[];

  var i = 0;
  while (i < windowed.length) {
    final m = windowed[i];

    if (m.role == CoachRole.user) {
      out.add(m.toProviderJson());
      i++;
      continue;
    }

    // A tool result reached on its own answers a call that is not here. The
    // window cut above it, or its assistant turn was never written.
    if (m.role == CoachRole.tool) {
      i++;
      continue;
    }

    final calls = m.toolCalls;
    if (calls == null || calls.isEmpty) {
      // An assistant row with neither text nor calls says nothing and is
      // rejected on its own merits.
      if ((m.content ?? '').trim().isNotEmpty) out.add(m.toProviderJson());
      i++;
      continue;
    }

    // Consecutive tool rows are the answers to this turn.
    var j = i + 1;
    final replies = <CoachMessage>[];
    while (j < windowed.length && windowed[j].role == CoachRole.tool) {
      replies.add(windowed[j]);
      j++;
    }

    final asked = {for (final c in calls) (c['id'] as String?) ?? ''};
    final answered = {for (final r in replies) r.toolCallId ?? ''};

    if (asked.isNotEmpty && asked.difference(answered).isEmpty) {
      out.add(m.toProviderJson());
      for (final r in replies) {
        if (asked.contains(r.toolCallId)) out.add(r.toProviderJson());
      }
    } else if ((m.content ?? '').trim().isNotEmpty) {
      // Half a group. Keep what the coach said, drop the bookkeeping — the
      // model loses the lookup, not the conversation.
      out.add({'role': 'assistant', 'content': m.content});
    }

    i = j;
  }

  return out;
}

/// The tail of the thread, cut at a turn boundary.
///
/// Cutting at an arbitrary offset is what put orphaned tool rows at the front
/// of the replay in the first place. A user message always starts a turn, so
/// the cut moves forward to one — under the budget rather than over it.
List<CoachMessage> _window(List<CoachMessage> history) {
  if (history.length <= kHistoryWindow) return history;

  var start = history.length - kHistoryWindow;
  while (start < history.length && history[start].role != CoachRole.user) {
    start++;
  }
  // No turn boundary in the tail at all: replay nothing rather than a
  // fragment. The question being asked still stands on its own.
  if (start >= history.length) return const [];
  return history.sublist(start);
}

class CoachService {
  final CoachTransport transport;

  CoachService({required this.transport});

  /// Runs one exchange to completion, executing tools locally as the model
  /// asks for them.
  Future<CoachTurn> send({
    required String question,
    required List<CoachMessage> history,
    required CoachContext context,
  }) async {
    final produced = <PendingMessage>[
      PendingMessage(role: CoachRole.user, content: question),
    ];
    final actions = <CoachAction>[];
    final toolsUsed = <String>[];

    // Replay the thread so the coach remembers what was already said and
    // already looked up.
    final wire = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(context)},
      ...replayHistory(history),
      {'role': 'user', 'content': question},
    ];

    for (var round = 0; round < kMaxToolRounds; round++) {
      final isLastRound = round == kMaxToolRounds - 1;

      final message = await transport.complete(
        messages: wire,
        // On the final round, drop the tools so the model has no choice but to
        // answer with what it already has.
        tools: isLastRound ? null : kCoachTools,
      );

      final calls = _toolCallsFrom(message);
      final content = message['content'] as String?;

      if (calls.isEmpty) {
        produced.add(PendingMessage(
          role: CoachRole.assistant,
          content: content,
          actions: actions,
        ));
        return CoachTurn(
          messages: produced,
          reply: (content ?? '').trim().isEmpty
              ? 'I could not put an answer together for that one. Try asking a '
                  'different way.'
              : content!.trim(),
          actions: actions,
          toolsUsed: toolsUsed,
        );
      }

      // Record what the model asked for, verbatim, so the thread replays.
      produced.add(PendingMessage(
        role: CoachRole.assistant,
        content: content,
        toolCalls: calls,
      ));
      wire.add({
        'role': 'assistant',
        'content': content,
        'tool_calls': calls,
      });

      for (final call in calls) {
        final fn = call['function'];
        final name = fn is Map ? (fn['name'] as String? ?? '') : '';
        final id = call['id'] as String? ?? '';
        final args = _decodeArgs(fn is Map ? fn['arguments'] : null);

        final result = runCoachTool(name: name, args: args, context: context);
        toolsUsed.add(name);
        if (result.action != null) actions.add(result.action!);

        produced.add(PendingMessage(
          role: CoachRole.tool,
          content: result.content,
          toolCallId: id,
          name: name,
        ));
        wire.add({
          'role': 'tool',
          'tool_call_id': id,
          'content': result.content,
        });
      }
    }

    // Should be unreachable — the last round runs without tools.
    return CoachTurn(
      messages: produced,
      reply: 'That took more steps than I can manage in one go. Try asking '
          'something narrower.',
      actions: actions,
      toolsUsed: toolsUsed,
    );
  }

  String _systemPrompt(CoachContext context) {
    final names = context.accounts.map((a) => a.name).join(', ');

    return '''
You are the user's personal money manager. They are in Ghana and everything is in GHS.
Today is ${dateLongFmt.format(context.snapshot.asOf)}.
Their accounts are: ${names.isEmpty ? '(none set up yet)' : names}.

How to work:
- Call tools for every fact. Never calculate anything yourself and never estimate
  a balance, a total or a date — get_position, plan_payment and get_spending have
  already done the arithmetic, and their numbers are the only ones you may quote.
- For "where should I pay this from" or "can I afford this", always call
  plan_payment. Do not reason about which account to use on your own.
- When the answer is "move money from one account to another", call
  propose_transfer so the user gets a button instead of a paragraph.
- If the user mentions a bill or salary that is not in list_commitments, offer to
  record it with propose_commitment.
- propose_transfer and propose_commitment do NOT do anything. They show the user
  a card to approve. Never say something has been done, moved or saved.

How to talk:
- Like a sharp friend who handles money well. Short sentences. No preamble, no
  greeting, no sign-off.
- Under 150 words unless they asked for detail.
- Always end with the specific next step, naming the account and the amount.
- If the data is missing, say exactly what to add rather than guessing around it.
''';
  }

  List<Map<String, dynamic>> _toolCallsFrom(Map<String, dynamic> message) {
    final raw = message['tool_calls'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
  }

  /// Arguments arrive as a JSON string. A model occasionally sends something
  /// malformed; an empty map lets the tool report the problem instead of
  /// crashing the turn.
  Map<String, dynamic> _decodeArgs(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }
}
