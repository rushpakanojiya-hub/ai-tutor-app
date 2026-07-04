import '../core/constants/api_constants.dart';
import '../models/conversation.dart';
import '../models/recommendation.dart';
import 'api_service.dart';

/// Result of one chat turn.
class ChatResult {
  final int conversationId;
  final String reply;
  ChatResult({required this.conversationId, required this.reply});
}

/// Structured homework-help response.
class HomeworkResult {
  final String explanation;
  final List<String> stepByStep;
  final List<String> examples;
  final List<String> tips;

  HomeworkResult({
    required this.explanation,
    required this.stepByStep,
    required this.examples,
    required this.tips,
  });

  factory HomeworkResult.fromJson(Map<String, dynamic> json) {
    return HomeworkResult(
      explanation: json['explanation'] as String? ?? '',
      stepByStep: (json['step_by_step'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      examples: (json['examples'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      tips: (json['tips'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
    );
  }
}

/// Talks to the backend's /api/ai/* endpoints (chat, conversations,
/// homework help, recommendations).
class AiService {
  final ApiService _api = ApiService();

  Future<ChatResult> sendMessage({
    required String message,
    int? conversationId,
    int? subjectId,
    String language = 'en',
  }) async {
    final response = await _api.post(ApiConstants.aiChat, {
      'message': message,
      if (conversationId != null) 'conversation_id': conversationId,
      if (subjectId != null) 'subject_id': subjectId,
      'language': language,
    });
    final data = response['data'] as Map<String, dynamic>;
    return ChatResult(conversationId: data['conversation_id'] as int, reply: data['reply'] as String);
  }

  Future<List<ConversationModel>> fetchConversations() async {
    final response = await _api.get(ApiConstants.aiConversations);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => ConversationModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<ConversationWithMessagesModel> fetchConversation(int id) async {
    final response = await _api.get(ApiConstants.aiConversation(id));
    return ConversationWithMessagesModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<void> deleteConversation(int id) async {
    await _api.delete(ApiConstants.aiConversation(id));
  }

  Future<HomeworkResult> requestHomeworkHelp({
    required String question,
    String subject = '',
    String difficulty = '',
  }) async {
    final response = await _api.post(ApiConstants.aiHomework, {
      'question': question,
      'subject': subject,
      'difficulty': difficulty,
    });
    return HomeworkResult.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<RecommendationModel>> fetchRecommendations() async {
    final response = await _api.get(ApiConstants.aiRecommendations);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => RecommendationModel.fromJson(json as Map<String, dynamic>)).toList();
  }
}
