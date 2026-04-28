class ChatMessage {
  final String id;
  final String userId;
  final String question;
  final String answer;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.userId,
    required this.question,
    required this.answer,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        question: j['question'] as String,
        answer: j['answer'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
