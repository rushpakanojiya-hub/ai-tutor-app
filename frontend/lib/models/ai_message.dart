/// A single chat message â€” either from the student ("user") or the AI
/// Tutor ("assistant"). Mirrors the backend's ai_messages table row.
class AiMessageModel {
  final int id;
  final int conversationId;
  final String role; // "user" | "assistant" | "system"
  final String message;
  final DateTime createdAt;

  AiMessageModel({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.message,
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  factory AiMessageModel.fromJson(Map<String, dynamic> json) {
    return AiMessageModel(
      id: json['id'] as int? ?? 0,
      conversationId: json['conversation_id'] as int? ?? 0,
      role: json['role'] as String? ?? 'assistant',
      message: json['message'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
