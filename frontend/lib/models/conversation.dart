import 'ai_message.dart';

/// A saved AI Tutor chat conversation. Mirrors the backend's
/// ai_conversations table row.
class ConversationModel {
  final int id;
  final int? subjectId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  ConversationModel({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as int? ?? 0,
      subjectId: json['subject_id'] as int?,
      title: json['title'] as String? ?? 'Conversation',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// A conversation with its full message history â€” returned by
/// GET /api/ai/conversations/:id.
class ConversationWithMessagesModel {
  final ConversationModel conversation;
  final List<AiMessageModel> messages;

  ConversationWithMessagesModel({required this.conversation, required this.messages});

  factory ConversationWithMessagesModel.fromJson(Map<String, dynamic> json) {
    return ConversationWithMessagesModel(
      conversation: ConversationModel.fromJson(json),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map((e) => AiMessageModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
