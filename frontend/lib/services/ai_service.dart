import '../core/constants/api_constants.dart';
import '../models/ai_session.dart';
import '../models/recommendation.dart';
import 'api_service.dart';

/// Result of one chat turn.
class ChatResult {
  final int sessionId;
  final String reply;
  ChatResult({required this.sessionId, required this.reply});
}

/// Talks to the backend's /api/ai/* endpoints. The backend is the only
/// thing that ever calls Groq - this service never holds or sends an API
/// key, matching the required Flutter -> Go -> Groq architecture. Homework
/// help isn't a separate endpoint: the same chat call carries a `mode`
/// flag ("normal" | "homework") that changes the system prompt server-side.
class AiService {
  final ApiService _api = ApiService();

  Future<ChatResult> sendMessage({
    required String message,
    int? sessionId,
    int? subjectId,
    String language = 'en',
    String mode = 'normal',
  }) async {
    final response = await _api.post(ApiConstants.aiChat, {
      'message': message,
      if (sessionId != null) 'session_id': sessionId,
      if (subjectId != null) 'subject_id': subjectId,
      'language': language,
      'mode': mode,
    });
    final data = response['data'] as Map<String, dynamic>;
    return ChatResult(sessionId: data['session_id'] as int, reply: data['reply'] as String);
  }

  Future<List<AiSessionModel>> fetchSessions() async {
    final response = await _api.get(ApiConstants.aiSessions);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => AiSessionModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<AiSessionWithMessagesModel> fetchSession(int id) async {
    final response = await _api.get(ApiConstants.aiSession(id));
    return AiSessionWithMessagesModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<void> deleteSession(int id) async {
    await _api.delete(ApiConstants.aiSession(id));
  }

  Future<List<RecommendationModel>> fetchRecommendations() async {
    final response = await _api.get(ApiConstants.aiRecommendations);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => RecommendationModel.fromJson(json as Map<String, dynamic>)).toList();
  }
}
