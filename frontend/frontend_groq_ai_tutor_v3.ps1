$files = @{}
$files['pubspec.yaml'] = @'
name: ai_tutor_app
description: AI Tutor Mobile Application MVP - Day 1 (Auth + Dashboard shell)
publish_to: 'none'
version: 0.1.0

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6

  # State management
  provider: ^6.1.2

  # Networking
  dio: ^5.4.3+1

  # Local storage (JWT token, user info)
  shared_preferences: ^2.2.3

  # Navigation
  go_router: ^14.2.0

  # Day 2: video playback
  video_player: ^2.9.1
  chewie: ^1.8.5

  # Day 2: PDF notes (opened externally to avoid native PDF-render plugin
  # Gradle conflicts with newer Android Gradle Plugin versions)
  url_launcher: ^6.3.0

  # UI redesign (visual only — no logic changes)
  google_fonts: ^6.2.1
  flutter_animate: ^4.5.0
  flutter_svg: ^2.0.10+1

  # AI Tutor: basic speech-to-text voice input
  speech_to_text: ^7.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true

'@
$files['lib\core\constants\api_constants.dart'] = @'
/// Centralized API configuration so base URLs and endpoint paths
/// only ever need to change in one place.
class ApiConstants {
  ApiConstants._();

  /// Android emulator maps 10.0.2.2 to the host machine's localhost.
  /// - Physical device / real backend: replace with your machine's LAN IP
  ///   or your deployed Render URL, e.g. https://your-app.onrender.com
  /// - iOS simulator: use http://localhost:8080
  static const String baseUrl = 'http://192.168.1.14:8080/api';

  // --- Day 1: Auth ---
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String profile = '/auth/profile';

  // --- Day 2: Course & Learning Management ---
  static const String categories = '/categories';
  static String categorySubjects(int categoryId) => '/categories/$categoryId/subjects';
  static const String subjects = '/subjects';
  static String subjectById(int subjectId) => '/subjects/$subjectId';
  static String subjectLessons(int subjectId) => '/subjects/$subjectId/lessons';
  static String lessonById(int lessonId) => '/lessons/$lessonId';
  static String lessonNotes(int lessonId) => '/lessons/$lessonId/notes';
  static String lessonAiContent(int lessonId) => '/lessons/$lessonId/ai-content';
  static const String search = '/search';

  // --- Progress tracking ---
  static String markLessonComplete(int lessonId) => '/progress/lessons/$lessonId/complete';
  static String subjectProgress(int subjectId) => '/progress/subjects/$subjectId';

  // --- AI Tutor ---
  static const String aiChat = '/ai/chat';
  static const String aiSessions = '/ai/sessions';
  static String aiSession(int id) => '/ai/sessions/$id';
  static const String aiRecommendations = '/ai/recommendations';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// Resolves a possibly-relative media path (e.g. "/static/notes/x.pdf",
  /// stored in the DB so it works on any host) into a full URL using the
  /// same host as [baseUrl]. Already-absolute URLs (http/https) pass through
  /// unchanged, so externally hosted media still works too.
  static String resolveMediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final origin = baseUrl.replaceAll('/api', '');
    return '$origin$path';
  }
}

'@
$files['lib\core\routes\app_router.dart'] = @'
import 'package:go_router/go_router.dart';
import '../../models/ai_content_model.dart';
import '../../providers/auth_provider.dart';
import '../../screens/ai/ai_chat_screen.dart';
import '../../screens/ai/ai_history_screen.dart';
import '../../screens/ai/ai_home_screen.dart';
import '../../screens/ai/recommendation_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/categories/categories_screen.dart';
import '../../screens/dashboard/dashboard_screen.dart';
import '../../screens/lessons/lesson_player_screen.dart';
import '../../screens/lessons/lessons_screen.dart';
import '../../screens/lessons/pdf_viewer_screen.dart';
import '../../screens/lessons/quiz_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/splash/splash_screen.dart';
import '../../screens/subjects/subjects_screen.dart';

/// Centralized GoRouter config with a redirect guard: unauthenticated users
/// are bounced to /login, authenticated users away from /login /register.
///
/// Day 2 routes (categories/subjects/lessons/player/pdf-viewer/search) all
/// sit "on top of" the authenticated area — none are reachable from
/// /login or /register, matching the Dashboard -> Categories -> ... flow.
class AppRouter {
  final AuthProvider authProvider;

  AppRouter(this.authProvider);

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    refreshListenable: authProvider,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),

      // --- Day 2: Course & Learning Management ---
      GoRoute(
        path: '/categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/subjects',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SubjectsScreen(
            categoryId: extra['categoryId'] as int? ?? 0,
            categoryName: extra['categoryName'] as String? ?? 'Subjects',
          );
        },
      ),
      GoRoute(
        path: '/lessons',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return LessonsScreen(
            subjectId: extra['subjectId'] as int? ?? 0,
            subjectName: extra['subjectName'] as String? ?? 'Lessons',
          );
        },
      ),
      GoRoute(
        path: '/lesson-player',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return LessonPlayerScreen(lessonId: extra['lessonId'] as int? ?? 0);
        },
      ),
      GoRoute(
        path: '/pdf-viewer',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PdfViewerScreen(
            url: extra['url'] as String? ?? '',
            title: extra['title'] as String? ?? 'Notes',
          );
        },
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/quiz',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return QuizScreen(
            lessonId: extra['lessonId'] as int? ?? 0,
            questions: (extra['questions'] as List<dynamic>? ?? []).cast<QuizQuestionModel>(),
          );
        },
      ),

      // --- Day 3: AI Tutor ---
      GoRoute(path: '/ai-tutor', builder: (context, state) => const AiHomeScreen()),
      GoRoute(
        path: '/ai-chat',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return AiChatScreen(sessionId: extra?['sessionId'] as int?);
        },
      ),
      GoRoute(path: '/ai-history', builder: (context, state) => const AiHistoryScreen()),
      GoRoute(path: '/ai-recommendations', builder: (context, state) => const RecommendationScreen()),
    ],
    redirect: (context, state) {
      final status = authProvider.status;
      final loggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/register';
      final onSplash = state.matchedLocation == '/';

      if (status == AuthStatus.unknown) {
        return onSplash ? null : '/';
      }
      if (status == AuthStatus.unauthenticated) {
        return loggingIn ? null : '/login';
      }
      if (status == AuthStatus.authenticated && (loggingIn || onSplash)) {
        return '/dashboard';
      }
      return null;
    },
  );
}

'@
$files['lib\services\api_service.dart'] = @'
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/app_constants.dart';
import 'storage_service.dart';

/// A normalized exception so the UI never has to deal with raw DioException.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Thin wrapper around Dio: base URL, timeouts, auth header injection,
/// and consistent error translation (Part 9: Error Handling).
class ApiService {
  late final Dio _dio;
  final StorageService _storage = StorageService();

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.getString(AppConstants.keyAuthToken);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(path, data: data);
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translateError(e);
    }
  }

  Future<Map<String, dynamic>> get(String path) async {
    try {
      final response = await _dio.get(path);
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translateError(e);
    }
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put(path, data: data);
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translateError(e);
    }
  }

  Future<Map<String, dynamic>> delete(String path) async {
    try {
      final response = await _dio.delete(path);
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translateError(e);
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  ApiException _translateError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException('Request timed out. Please check your internet connection.');
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiException('Unable to reach the server. Please check your network.');
    }

    final response = e.response;
    if (response != null) {
      final data = response.data;
      String message = 'Something went wrong. Please try again.';
      if (data is Map && data['message'] != null) {
        message = data['message'].toString();
      }
      return ApiException(message, statusCode: response.statusCode);
    }

    return ApiException('Unexpected error occurred. Please try again.');
  }
}

'@
$files['lib\services\ai_service.dart'] = @'
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
/// help isn't a separate endpoint: students just ask their homework
/// question through the same chat (the real LLM solves it directly, step
/// by step, without needing a dedicated code path).
class AiService {
  final ApiService _api = ApiService();

  Future<ChatResult> sendMessage({
    required String message,
    int? sessionId,
    int? subjectId,
    String language = 'en',
  }) async {
    final response = await _api.post(ApiConstants.aiChat, {
      'message': message,
      if (sessionId != null) 'session_id': sessionId,
      if (subjectId != null) 'subject_id': subjectId,
      'language': language,
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

'@
$files['lib\providers\ai_provider.dart'] = @'
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
/// Homework help isn't a separate flow: students just type their homework
/// question into chat and the real LLM solves it directly.
class AiProvider extends ChangeNotifier {
  final AiService _service = AiService();

  // --- Chat ---
  List<AiMessageModel> messages = [];
  int? currentSessionId;
  int? currentSubjectId;
  bool isSending = false;
  String? chatError;
  String language = 'en'; // 'en' | 'hi' | 'mr'

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

'@
$files['lib\models\ai_message.dart'] = @'
/// A single chat message — either from the student ("user") or the AI
/// Tutor ("assistant"). Mirrors the backend's ai_chat_messages table row.
class AiMessageModel {
  final int id;
  final int sessionId;
  final String role; // "user" | "assistant" | "system"
  final String message;
  final DateTime createdAt;

  /// True while this message's text is still streaming in from the AI
  /// Tutor — used by ChatBubble to suppress copy/retry/delete actions
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

  /// Returns a copy with updated text/streaming state — used to append
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

'@
$files['lib\models\ai_session.dart'] = @'
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

/// A session with its full message history — returned by
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

'@
$files['lib\widgets\chat_bubble.dart'] = @'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/snackbar_utils.dart';
import '../models/ai_message.dart';

/// One chat message bubble: user messages align right (purple), AI
/// messages align left (white card) with lightweight markdown rendering
/// (**bold**, numbered/bulleted lists). Long-press reveals Copy/Retry/
/// Delete actions (disabled while the message is still streaming in).
class ChatBubble extends StatelessWidget {
  final AiMessageModel message;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  const ChatBubble({super.key, required this.message, this.onRetry, this.onDelete});

  void _showActions(BuildContext context) {
    if (message.isStreaming) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.message));
                Navigator.pop(context);
                SnackbarUtils.showSuccess(context, 'Copied to clipboard');
              },
            ),
            if (message.isUser && onRetry != null)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Retry'),
                onTap: () {
                  Navigator.pop(context);
                  onRetry!();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: const Text('Delete', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  /// Renders a small, dependency-free subset of markdown: **bold** spans,
  /// and lines starting with "- " or "1. " get a bullet/number prefix.
  /// This isn't a full markdown parser — just enough to make Groq's
  /// naturally-formatted replies (which often use **bold** and lists)
  /// readable without adding a new native package dependency.
  Widget _renderContent(bool isUser) {
    final color = isUser ? Colors.white : AppColors.textPrimary;
    final lines = message.message.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        final spans = _parseBold(line, color);
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: RichText(text: TextSpan(style: TextStyle(color: color, height: 1.4, fontSize: 14), children: spans)),
        );
      }).toList(),
    );
  }

  List<TextSpan> _parseBold(String line, Color color) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > last) {
        spans.add(TextSpan(text: line.substring(last, match.start)));
      }
      spans.add(TextSpan(text: match.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      last = match.end;
    }
    if (last < line.length) {
      spans.add(TextSpan(text: line.substring(last)));
    }
    if (spans.isEmpty) spans.add(const TextSpan(text: ''));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showActions(context),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              decoration: BoxDecoration(
                color: isUser ? AppColors.purple : AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: message.message.isEmpty && message.isStreaming
                  ? const SizedBox(width: 20, height: 14)
                  : _renderContent(isUser),
            ),
            if (!(message.message.isEmpty && message.isStreaming))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(_formatTime(message.createdAt), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

'@
$files['lib\widgets\typing_indicator.dart'] = @'
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Three animated dots shown in a chat bubble while waiting for the AI
/// Tutor's reply.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_controller.value - (i * 0.2)) % 1.0;
                final scale = 0.6 + (0.4 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0));
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: AppColors.textSecondary, shape: BoxShape.circle),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

'@
$files['lib\widgets\voice_input_button.dart'] = @'
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/theme/app_colors.dart';

/// Basic speech-to-text mic button: tap to start listening, tap again to
/// stop. Converts speech to text and hands it to [onResult] — no
/// text-to-speech, per the "voice input only" scope.
///
/// If the device denies microphone permission or speech recognition isn't
/// available, the button disables itself instead of crashing — needs
/// RECORD_AUDIO permission declared in AndroidManifest.xml.
class VoiceInputButton extends StatefulWidget {
  final void Function(String text) onResult;

  const VoiceInputButton({super.key, required this.onResult});

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isAvailable = true;
  bool _checked = false;

  Future<void> _ensureInitialized() async {
    if (_checked) return;
    _checked = true;
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (mounted) setState(() => _isAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _isAvailable = false);
    }
  }

  Future<void> _toggleListening() async {
    await _ensureInitialized();
    if (!_isAvailable) return;

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);
    try {
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            widget.onResult(result.recognizedWords);
          }
        },
      );
    } catch (_) {
      if (mounted) setState(() => _isListening = false);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _isAvailable ? _toggleListening : null,
      tooltip: _isAvailable ? 'Voice input' : 'Voice input unavailable',
      icon: Icon(
        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: _isListening ? AppColors.error : (_isAvailable ? AppColors.purple : AppColors.textSecondary),
      ),
    );
  }
}

'@
$files['lib\screens\ai\ai_home_screen.dart'] = @'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// AI Tutor home: entry points to chat, homework help, chat history, and
/// recommendations. Reached from the Dashboard's "AI Tutor" card / bottom
/// nav tab.
class AiHomeScreen extends StatelessWidget {
  const AiHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Tutor')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How can I help you learn today?',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _card(
              context,
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.purple,
              bg: AppColors.purpleLight,
              title: 'Ask Question',
              subtitle: 'Chat with a real AI Tutor about any subject',
              onTap: () => context.push('/ai-chat'),
            ),
            const SizedBox(height: 14),
            _card(
              context,
              icon: Icons.edit_note_rounded,
              color: AppColors.orange,
              bg: AppColors.orangeLight,
              title: 'Homework Help',
              subtitle: 'Get step-by-step help with your homework',
              onTap: () => context.push('/ai-chat'),
            ),
            const SizedBox(height: 14),
            _card(
              context,
              icon: Icons.history_rounded,
              color: AppColors.blue,
              bg: AppColors.blueLight,
              title: 'Chat History',
              subtitle: 'Revisit your past conversations',
              onTap: () => context.push('/ai-history'),
            ),
            const SizedBox(height: 14),
            _card(
              context,
              icon: Icons.auto_awesome_rounded,
              color: AppColors.green,
              bg: AppColors.greenLight,
              title: 'Recommendations',
              subtitle: 'See what to learn next',
              onTap: () => context.push('/ai-recommendations'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required Color bg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

'@
$files['lib\screens\ai\ai_chat_screen.dart'] = @'
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/subject_model.dart';
import '../../providers/ai_provider.dart';
import '../../services/subject_service.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/typing_indicator.dart';
import '../../widgets/voice_input_button.dart';

/// AI Tutor chat: pick a subject (optional, for subject-aware answers),
/// then chat with a real LLM (Groq, via the backend). Supports English/
/// Hindi/Marathi replies, a ChatGPT-style typing animation, and basic
/// speech-to-text voice input.
class AiChatScreen extends StatefulWidget {
  /// If opened from AiHistoryScreen to resume a saved session.
  final int? sessionId;

  const AiChatScreen({super.key, this.sessionId});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final SubjectService _subjectService = SubjectService();

  List<SubjectModel> _subjects = [];
  int? _selectedSubjectId;
  bool _loadingSubjects = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _subjects = await _subjectService.fetchAllSubjects();
    } catch (_) {
      _subjects = [];
    }
    if (mounted) setState(() => _loadingSubjects = false);

    if (widget.sessionId != null) {
      await context.read<AiProvider>().loadSessionIntoChat(widget.sessionId!);
      if (mounted) setState(() => _selectedSubjectId = context.read<AiProvider>().currentSubjectId);
    } else {
      context.read<AiProvider>().startNewChat();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    final provider = context.read<AiProvider>();
    provider.currentSubjectId = _selectedSubjectId;
    await provider.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiProvider>();
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Tutor Chat'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate_rounded),
            tooltip: 'Language',
            onSelected: (lang) => context.read<AiProvider>().setLanguage(lang),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'hi', child: Text('हिंदी (Hindi)')),
              PopupMenuItem(value: 'mr', child: Text('मराठी (Marathi)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_loadingSubjects && _subjects.isNotEmpty) _buildSubjectSelector(),
          Expanded(child: _buildMessageList(provider)),
          if (provider.chatError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: Text(provider.chatError!, style: const TextStyle(color: AppColors.error, fontSize: 12))),
                  TextButton(onPressed: () => provider.retryLast(), child: const Text('Retry')),
                ],
              ),
            ),
          _buildInputBar(provider),
        ],
      ),
    );
  }

  Widget _buildSubjectSelector() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _subjectChip(null, 'General'),
          ..._subjects.map((s) => _subjectChip(s.id, s.name)),
        ],
      ),
    );
  }

  Widget _subjectChip(int? id, String label) {
    final selected = _selectedSubjectId == id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _selectedSubjectId = id),
        selectedColor: AppColors.purpleLight,
        labelStyle: TextStyle(color: selected ? AppColors.purple : AppColors.textSecondary, fontSize: 12),
      ),
    );
  }

  Widget _buildMessageList(AiProvider provider) {
    if (provider.messages.isEmpty && !provider.isSending) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.smart_toy_outlined, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text('Ask me anything about your subjects!', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    // Show the separate typing-dots indicator only before the streaming
    // assistant bubble has received its first chunk (after that, the
    // growing bubble itself is the "typing" signal).
    final showTypingDots = provider.isSending &&
        provider.messages.isNotEmpty &&
        !provider.messages.last.isUser &&
        provider.messages.last.message.isEmpty;

    final displayMessages = showTypingDots ? provider.messages.sublist(0, provider.messages.length - 1) : provider.messages;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: displayMessages.length + (showTypingDots ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == displayMessages.length) {
          return const Padding(padding: EdgeInsets.only(bottom: 8), child: TypingIndicator());
        }
        final message = displayMessages[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ChatBubble(
            message: message,
            onRetry: message.isUser ? () => provider.retryLast() : null,
            onDelete: () => provider.deleteMessageLocally(message.id),
          ),
        );
      },
    );
  }

  Widget _buildInputBar(AiProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            VoiceInputButton(onResult: (text) => _controller.text = text),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Ask a question...',
                  filled: true,
                  fillColor: AppColors.pageBackground,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _send(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(color: AppColors.purple, shape: BoxShape.circle),
              child: IconButton(
                onPressed: provider.isSending ? null : _send,
                icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

'@
$files['lib\screens\ai\ai_history_screen.dart'] = @'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/ai_provider.dart';
import '../../widgets/skeleton_box.dart';

/// Lists the student's saved AI Tutor chat sessions. Tapping one resumes
/// it in AiChatScreen; long-pressing or tapping the delete icon removes it.
class AiHistoryScreen extends StatefulWidget {
  const AiHistoryScreen({super.key});

  @override
  State<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends State<AiHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AiProvider>().loadSessions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Chat History')),
      body: RefreshIndicator(
        onRefresh: () => provider.loadSessions(),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(provider),
        ),
      ),
    );
  }

  Widget _buildBody(AiProvider provider) {
    if (provider.isLoadingSessions) {
      return ListView.separated(
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => SkeletonBox(height: 64, borderRadius: BorderRadius.circular(16)),
      );
    }

    if (provider.sessionsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(provider.sessionsError!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => provider.loadSessions(), child: const Text('Retry')),
          ],
        ),
      );
    }

    if (provider.sessions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('No chat history yet.', style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 4),
            Text('Start a conversation with the AI Tutor!', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: provider.sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final session = provider.sessions[index];
        return Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/ai-chat', extra: {'sessionId': session.id}),
            onLongPress: () => _confirmDelete(context, provider, session.id),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.purple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                    onPressed: () => _confirmDelete(context, provider, session.id),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, AiProvider provider, int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteSession(id);
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

'@
$files['lib\screens\dashboard\dashboard_screen.dart'] = @'
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subject_progress_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/lesson_service.dart';
import '../../services/storage_service.dart';
import '../categories/categories_screen.dart';
import '../ai/ai_home_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/skeleton_box.dart';

/// Student dashboard shell. UI redesign only — navigation targets,
/// providers, and the tab list are unchanged from before.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  final _pages = const [
    _DashboardHome(),
    CategoriesScreen(),
    AiHomeScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Courses'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'AI Tutor'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _DashboardHome extends StatefulWidget {
  const _DashboardHome();

  @override
  State<_DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<_DashboardHome> {
  final LessonService _lessonService = LessonService();
  final StorageService _storage = StorageService();

  int? _lastSubjectId;
  String? _lastSubjectName;
  SubjectProgressModel? _lastSubjectProgress;
  bool _loadingProgress = true;

  @override
  void initState() {
    super.initState();
    _loadContinueLearning();
  }

  /// Reads the most recently opened subject (saved by LessonsScreen) and
  /// fetches its real completion percentage from the backend. If the user
  /// hasn't opened any subject yet, this stays null and the dashboard falls
  /// back to the illustrative example cards below.
  Future<void> _loadContinueLearning() async {
    final id = await _storage.getInt(AppConstants.keyLastSubjectId);
    final name = await _storage.getString(AppConstants.keyLastSubjectName);

    if (id != null && name != null) {
      try {
        final progress = await _lessonService.fetchSubjectProgress(id);
        if (mounted) {
          setState(() {
            _lastSubjectId = id;
            _lastSubjectName = name;
            _lastSubjectProgress = progress;
          });
        }
      } catch (_) {
        // No connectivity / subject deleted — fall back to example cards.
      }
    }

    if (mounted) setState(() => _loadingProgress = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'Hello, ${user?.name ?? 'Student'} \u{1F44B}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0),
        const SizedBox(height: 4),
        const Text(
          'Ready to continue learning today?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ).animate().fadeIn(duration: 350.ms, delay: 80.ms),
        const SizedBox(height: 24),

        _DashboardActionCard(
          icon: Icons.menu_book_rounded,
          iconBg: AppColors.purpleLight,
          iconColor: AppColors.purple,
          title: 'My Courses',
          subtitle: 'Continue learning',
          onTap: () => context.push('/categories'),
        ).animate().fadeIn(duration: 300.ms, delay: 100.ms).slideY(begin: 0.15, end: 0),
        const SizedBox(height: 14),
        _DashboardActionCard(
          icon: Icons.smart_toy_rounded,
          iconBg: AppColors.orangeLight,
          iconColor: AppColors.orange,
          title: 'AI Tutor',
          subtitle: 'Ask anything',
          onTap: () => context.push('/ai-tutor'),
        ).animate().fadeIn(duration: 300.ms, delay: 160.ms).slideY(begin: 0.15, end: 0),
        const SizedBox(height: 14),
        _DashboardActionCard(
          icon: Icons.help_outline_rounded,
          iconBg: AppColors.blueLight,
          iconColor: AppColors.blue,
          title: 'Quiz',
          subtitle: 'Test your knowledge',
          onTap: () => _showComingSoon(context, 'Quiz'),
        ).animate().fadeIn(duration: 300.ms, delay: 220.ms).slideY(begin: 0.15, end: 0),
        const SizedBox(height: 14),
        _DashboardActionCard(
          icon: Icons.trending_up_rounded,
          iconBg: AppColors.greenLight,
          iconColor: AppColors.green,
          title: 'Progress',
          subtitle: 'Track your growth',
          onTap: () => _showComingSoon(context, 'Progress'),
        ).animate().fadeIn(duration: 300.ms, delay: 280.ms).slideY(begin: 0.15, end: 0),

        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Continue Learning', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            TextButton(
              onPressed: () => context.push('/categories'),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildContinueLearning(),
      ],
    );
  }

  Widget _buildContinueLearning() {
    if (_loadingProgress) {
      return SkeletonBox(height: 84, borderRadius: BorderRadius.circular(20));
    }

    // Real data: the subject the user most recently opened, with its
    // actual completion percentage from the backend.
    if (_lastSubjectId != null && _lastSubjectProgress != null) {
      final p = _lastSubjectProgress!;
      return _ContinueLearningCard(
        title: _lastSubjectName!,
        meta: '${p.completedLessons} of ${p.totalLessons} lessons complete',
        progress: p.percentage,
        icon: Icons.menu_book_rounded,
        color: AppColors.purple,
        onTap: () => context.push('/lessons', extra: {'subjectId': _lastSubjectId, 'subjectName': _lastSubjectName}),
      ).animate().fadeIn(duration: 300.ms, delay: 340.ms);
    }

    // No subject opened yet — illustrative example so the section isn't
    // empty on a brand-new account. Tapping it leads into real categories.
    return Column(
      children: [
        _ContinueLearningCard(
          title: 'Mathematics Basics',
          meta: 'Start your first lesson',
          progress: 0,
          icon: Icons.calculate_rounded,
          color: AppColors.orange,
          onTap: () => context.push('/categories'),
        ).animate().fadeIn(duration: 300.ms, delay: 340.ms),
      ],
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming in a later build'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Full-width vertical action card used for My Courses / AI Tutor / Quiz /
/// Progress on the dashboard home tab.
class _DashboardActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DashboardActionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: iconBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: iconColor.withOpacity(0.15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: iconColor)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: iconColor.withOpacity(0.85))),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Continue Learning" card: subject icon, progress bar, and a Continue
/// button.
class _ContinueLearningCard extends StatelessWidget {
  final String title;
  final String meta;
  final double progress;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ContinueLearningCard({
    required this.title,
    required this.meta,
    required this.progress,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(meta, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: color.withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  final String title;
  const _PlaceholderTab({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('$title - coming soon', style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
    );
  }
}

'@

foreach ($path in $files.Keys) {
    $fullPath = Join-Path $PWD $path
    $dir = Split-Path $fullPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($fullPath, $files[$path], [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated: $path"
}

$staleFiles = @(
    "lib\screens\ai\homework_screen.dart",
    "lib\screens\ai\ai_tutor_screen.dart",
    "lib\models\conversation.dart",
    "lib\widgets\voice_button.dart"
)

foreach ($stale in $staleFiles) {
    $full = Join-Path $PWD $stale
    if (Test-Path $full) {
        Remove-Item $full -Force
        Write-Host "Removed stale file: $stale"
    }
}

Write-Host "Frontend Groq AI Tutor files applied (with debug logging)."
