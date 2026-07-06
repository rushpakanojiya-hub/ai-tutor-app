import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ai_message.dart';
import '../models/ai_session.dart';
import '../models/recommendation.dart';
import '../services/ai_service.dart';
import '../services/api_service.dart';

/// Holds AI Tutor chat, session history, and recommendation state. Every
/// reply comes from the backend's POST /api/ai/chat, which is the only
/// thing that ever calls Groq - the API key never touches the client.
/// Homework help isn't a separate flow: it's a mode flag sent alongside
/// the same chat message, which changes the system prompt server-side.
class AiProvider extends ChangeNotifier {
  final AiService _service = AiService();

  // --- Chat ---
  List<AiMessageModel> messages = [];
  int? currentSessionId;
  int? currentSubjectId;
  bool isSending = false;
  String? chatError;
  String language = 'en'; // 'en' | 'hi' | 'mr'
  bool homeworkMode = false;

  String _lastUserMessage = '';

  void startNewChat({int? subjectId}) {
    messages = [];
    currentSessionId = null;
    currentSubjectId = subjectId;
    chatError = null;
    notifyListeners();
  }

  void setLanguage(String lang) {
    language = lang;
    notifyListeners();
  }

  void setSubject(int? subjectId) {
    currentSubjectId = subjectId;
    notifyListeners();
  }

  void toggleHomeworkMode() {
    homeworkMode = !homeworkMode;
    notifyListeners();
  }

  /// Sends a message, waits for the AI Tutor's full reply, then reveals it
  /// with a word-by-word typing animation (ChatGPT-style) - the backend
  /// call itself is a single request/response, not a live network stream.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final trimmed = text.trim();
    _lastUserMessage = trimmed;

    messages.add(AiMessageModel(
      id: DateTime.now().microsecondsSinceEpoch,
      sessionId: currentSessionId ?? 0,
      role: 'user',
      message: trimmed,
      createdAt: DateTime.now(),
    ));
    isSending = true;
    chatError = null;
    notifyListeners();

    try {
      final result = await _service.sendMessage(
        message: trimmed,
        sessionId: currentSessionId,
        subjectId: currentSubjectId,
        language: language,
        mode: homeworkMode ? 'homework' : 'normal',
      );
      currentSessionId = result.sessionId;
      isSending = false;

      await _revealTyped(result.sessionId, result.reply);
    } on ApiException catch (e) {
      debugPrint('[AiProvider] ApiException: ${e.message} (status ${e.statusCode})');
      chatError = e.message;
      isSending = false;
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('[AiProvider] Unexpected error in sendMessage: $e');
      debugPrint('[AiProvider] Stack trace: $stackTrace');
      chatError = 'Could not reach the AI Tutor. Please try again.';
      isSending = false;
      notifyListeners();
    }
  }

  /// Reveals [fullText] into a new assistant message a few words at a time,
  /// giving a typing-animation effect for the UI's "Chat UI" requirement.
  Future<void> _revealTyped(int sessionId, String fullText) async {
    final assistantId = DateTime.now().microsecondsSinceEpoch;
    var current = AiMessageModel(
      id: assistantId,
      sessionId: sessionId,
      role: 'assistant',
      message: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    );
    messages.add(current);
    notifyListeners();

    final words = fullText.split(' ');
    final buffer = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      buffer.write(i == 0 ? words[i] : ' ${words[i]}');
      final index = messages.indexWhere((m) => m.id == assistantId);
      if (index == -1) return; // message was deleted mid-animation
      current = current.copyWith(message: buffer.toString());
      messages[index] = current;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 18));
    }

    final index = messages.indexWhere((m) => m.id == assistantId);
    if (index != -1) {
      messages[index] = messages[index].copyWith(isStreaming: false);
      notifyListeners();
    }
  }

  /// Re-sends the last user message (used by ChatBubble's "Retry" action).
  Future<void> retryLast() async {
    if (_lastUserMessage.isEmpty) return;
    messages.removeWhere((m) => m.isUser && m.message == _lastUserMessage);
    await sendMessage(_lastUserMessage);
  }

  /// Regenerates a specific assistant reply: removes that assistant
  /// message (and the user message that prompted it), then re-sends the
  /// same question fresh - used by ChatBubble's "Regenerate" action.
  Future<void> regenerate(int assistantMessageId) async {
    final idx = messages.indexWhere((m) => m.id == assistantMessageId);
    if (idx <= 0) return;

    String? userText;
    for (var i = idx - 1; i >= 0; i--) {
      if (messages[i].isUser) {
        userText = messages[i].message;
        break;
      }
    }
    if (userText == null) return;

    messages.removeAt(idx);
    messages.removeWhere((m) => m.isUser && m.message == userText);
    await sendMessage(userText);
  }

  void deleteMessageLocally(int messageId) {
    messages.removeWhere((m) => m.id == messageId);
    notifyListeners();
  }

  Future<void> loadSessionIntoChat(int sessionId) async {
    isSending = false;
    chatError = null;
    notifyListeners();
    try {
      final session = await _service.fetchSession(sessionId);
      currentSessionId = session.session.id;
      currentSubjectId = session.session.subjectId;
      messages = session.messages;
    } catch (e) {
      chatError = 'Could not load this conversation.';
    }
    notifyListeners();
  }

  // --- Session history ---
  List<AiSessionModel> sessions = [];
  bool isLoadingSessions = false;
  String? sessionsError;

  Future<void> loadSessions() async {
    isLoadingSessions = true;
    sessionsError = null;
    notifyListeners();
    try {
      sessions = await _service.fetchSessions();
    } on ApiException catch (e) {
      sessionsError = e.message;
    } catch (e) {
      sessionsError = 'Could not load chat history.';
    }
    isLoadingSessions = false;
    notifyListeners();
  }

  Future<void> deleteSession(int id) async {
    try {
      await _service.deleteSession(id);
      sessions.removeWhere((s) => s.id == id);
      if (currentSessionId == id) {
        startNewChat();
      }
      notifyListeners();
    } catch (_) {
      // best-effort
    }
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
