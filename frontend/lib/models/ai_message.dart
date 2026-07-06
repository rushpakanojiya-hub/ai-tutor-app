/// A single chat message â€” either from the student ("user") or the AI
/// Tutor ("assistant"). Mirrors the backend's ai_chat_messages table row.
class AiMessageModel {
  final int id;
  final int sessionId;
  final String role; // "user" | "assistant" | "system"
  final String message;
  final DateTime createdAt;

  /// True while this message's text is still streaming in from the AI
  /// Tutor â€” used by ChatBubble to suppress copy/retry/delete actions
  /// until the reply has finished arriving.
  final bool isStreaming;

  AiMessageModel({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.message,
    required this.createdAt,
    this.isStreaming = false,
  });

  bool get isUser => role == 'user';

  /// Returns a copy with updated text/streaming state â€” used to append
  /// incoming chunks to the in-progress assistant message bubble.
  AiMessageModel copyWith({String? message, bool? isStreaming}) {
    return AiMessageModel(
      id: id,
      sessionId: sessionId,
      role: role,
      message: message ?? this.message,
      createdAt: createdAt,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  factory AiMessageModel.fromJson(Map<String, dynamic> json) {
    return AiMessageModel(
      id: json['id'] as int? ?? 0,
      sessionId: json['session_id'] as int? ?? 0,
      role: json['role'] as String? ?? 'assistant',
      message: json['message'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
