import 'package:flutter/material.dart';
import '../models/ai_message.dart';
import '../models/conversation.dart';
import '../models/recommendation.dart';
import '../services/ai_service.dart';
import '../services/api_service.dart';

/// Holds AI Tutor chat, conversation history, homework, and recommendation
/// state. All persistence goes through the backend's /api/ai/* endpoints â€”
/// there is no on-device or third-party AI call; replies come from the
/// backend's rule-based knowledge engine.
class AiProvider extends ChangeNotifier {
  final AiService _service = AiService();

  // --- Chat ---
  List<AiMessageModel> messages = [];
  int? currentConversationId;
  int? currentSubjectId;
  bool isSending = false;
  String? chatError;
  String language = 'en'; // 'en' | 'hi' | 'mr'

  void startNewChat({int? subjectId}) {
    messages = [];
    currentConversationId = null;
    currentSubjectId = subjectId;
    chatError = null;
    notifyListeners();
  }

  void setLanguage(String lang) {
    language = lang;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = AiMessageModel(
      id: DateTime.now().microsecondsSinceEpoch,
      conversationId: currentConversationId ?? 0,
      role: 'user',
      message: text.trim(),
      createdAt: DateTime.now(),
    );
    messages.add(userMessage);
    isSending = true;
    chatError = null;
    notifyListeners();

    try {
      final result = await _service.sendMessage(
        message: text.trim(),
        conversationId: currentConversationId,
        subjectId: currentSubjectId,
        language: language,
      );
      currentConversationId = result.conversationId;
      messages.add(AiMessageModel(
        id: DateTime.now().microsecondsSinceEpoch + 1,
        conversationId: result.conversationId,
        role: 'assistant',
        message: result.reply,
        createdAt: DateTime.now(),
      ));
    } on ApiException catch (e) {
      chatError = e.message;
    } catch (e) {
      chatError = 'Could not reach the AI Tutor. Please try again.';
    }

    isSending = false;
    notifyListeners();
  }

  /// Re-sends the last user message (used by the chat bubble's "Retry"
  /// action when a reply failed to arrive).
  Future<void> retryLast() async {
    final lastUser = messages.lastWhere((m) => m.isUser, orElse: () => messages.isEmpty ? AiMessageModel(id: 0, conversationId: 0, role: 'user', message: '', createdAt: DateTime.now()) : messages.last);
    if (lastUser.message.isEmpty) return;
    messages.removeWhere((m) => m.id == lastUser.id);
    await sendMessage(lastUser.message);
  }

  void deleteMessageLocally(int messageId) {
    messages.removeWhere((m) => m.id == messageId);
    notifyListeners();
  }

  Future<void> loadConversationIntoChat(int conversationId) async {
    isSending = false;
    chatError = null;
    notifyListeners();
    try {
      final conv = await _service.fetchConversation(conversationId);
      currentConversationId = conv.conversation.id;
      currentSubjectId = conv.conversation.subjectId;
      messages = conv.messages;
    } catch (e) {
      chatError = 'Could not load this conversation.';
    }
    notifyListeners();
  }

  // --- Conversation history ---
  List<ConversationModel> conversations = [];
  bool isLoadingConversations = false;
  String? conversationsError;

  Future<void> loadConversations() async {
    isLoadingConversations = true;
    conversationsError = null;
    notifyListeners();
    try {
      conversations = await _service.fetchConversations();
    } on ApiException catch (e) {
      conversationsError = e.message;
    } catch (e) {
      conversationsError = 'Could not load chat history.';
    }
    isLoadingConversations = false;
    notifyListeners();
  }

  Future<void> deleteConversation(int id) async {
    try {
      await _service.deleteConversation(id);
      conversations.removeWhere((c) => c.id == id);
      notifyListeners();
    } catch (_) {
      // best-effort
    }
  }

  // --- Homework ---
  HomeworkResult? homeworkResult;
  bool isLoadingHomework = false;
  String? homeworkError;

  Future<void> submitHomework({required String question, String subject = '', String difficulty = ''}) async {
    isLoadingHomework = true;
    homeworkError = null;
    homeworkResult = null;
    notifyListeners();
    try {
      homeworkResult = await _service.requestHomeworkHelp(question: question, subject: subject, difficulty: difficulty);
    } on ApiException catch (e) {
      homeworkError = e.message;
    } catch (e) {
      homeworkError = 'Could not get homework help. Please try again.';
    }
    isLoadingHomework = false;
    notifyListeners();
  }

  // --- Recommendations ---
  List<RecommendationModel> recommendations = [];
  bool isLoadingRecommendations = false;
  String? recommendationsError;

  Future<void> loadRecommendations() async {
    isLoadingRecommendations = true;
    recommendationsError = null;
    notifyListeners();
    try {
      recommendations = await _service.fetchRecommendations();
    } on ApiException catch (e) {
      recommendationsError = e.message;
    } catch (e) {
      recommendationsError = 'Could not load recommendations.';
    }
    isLoadingRecommendations = false;
    notifyListeners();
  }
}
