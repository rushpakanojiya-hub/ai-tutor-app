import 'ai_message.dart';

/// A saved AI Tutor chat session. Mirrors the backend's ai_chat_sessions
/// table row.
class AiSessionModel {
  final int id;
  final int? subjectId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  AiSessionModel({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiSessionModel.fromJson(Map<String, dynamic> json) {
    return AiSessionModel(
      id: json['id'] as int? ?? 0,
      subjectId: json['subject_id'] as int?,
      title: json['title'] as String? ?? 'Chat',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// A session with its full message history â€” returned by
/// GET /api/ai/sessions/:id.
class AiSessionWithMessagesModel {
  final AiSessionModel session;
  final List<AiMessageModel> messages;

  AiSessionWithMessagesModel({required this.session, required this.messages});

  factory AiSessionWithMessagesModel.fromJson(Map<String, dynamic> json) {
    return AiSessionWithMessagesModel(
      session: AiSessionModel.fromJson(json),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map((e) => AiMessageModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
