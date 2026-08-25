import 'coach_action.dart';

enum CoachRole {
  user('user'),
  assistant('assistant'),
  tool('tool');

  final String wire;
  const CoachRole(this.wire);

  static CoachRole fromWire(String s) =>
      values.firstWhere((r) => r.wire == s, orElse: () => CoachRole.assistant);
}

/// One turn in a conversation that the coach can actually remember.
///
/// Tool calls and their results are stored alongside the visible text, because
/// replaying only the prose would leave the model unable to see what it had
/// already looked up.
class CoachMessage {
  final String id;
  final String threadId;
  final CoachRole role;

  /// Null on an assistant turn that only requested tools.
  final String? content;

  /// Provider-shaped tool calls this assistant turn asked for.
  final List<Map<String, dynamic>>? toolCalls;

  /// Set on tool results: which call this answers, and the tool's name.
  final String? toolCallId;
  final String? name;

  /// Proposals attached to this turn. Nothing here has been applied.
  final List<CoachAction> actions;

  final DateTime createdAt;

  const CoachMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
    this.name,
    this.actions = const [],
    required this.createdAt,
  });

  /// Whether this message is something the user should see, as opposed to
  /// bookkeeping the model needs.
  bool get isVisible =>
      role == CoachRole.user ||
      (role == CoachRole.assistant && (content?.trim().isNotEmpty ?? false));

  /// The shape the provider expects when replaying history.
  Map<String, dynamic> toProviderJson() => switch (role) {
        CoachRole.user => {'role': 'user', 'content': content ?? ''},
        CoachRole.assistant => {
            'role': 'assistant',
            'content': content,
            if (toolCalls != null && toolCalls!.isNotEmpty)
              'tool_calls': toolCalls,
          },
        CoachRole.tool => {
            'role': 'tool',
            'tool_call_id': toolCallId ?? '',
            'content': content ?? '',
          },
      };

  factory CoachMessage.fromJson(Map<String, dynamic> j) {
    final rawCalls = j['tool_calls'];
    final rawActions = j['actions'];

    return CoachMessage(
      id: j['id'] as String,
      threadId: j['thread_id'] as String,
      role: CoachRole.fromWire(j['role'] as String),
      content: j['content'] as String?,
      toolCalls: rawCalls is List
          ? rawCalls.cast<Map<String, dynamic>>()
          : null,
      toolCallId: j['tool_call_id'] as String?,
      name: j['name'] as String?,
      actions: rawActions is List
          ? rawActions
              .whereType<Map<String, dynamic>>()
              .map(CoachAction.fromJson)
              .whereType<CoachAction>()
              .toList()
          : const [],
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }
}
