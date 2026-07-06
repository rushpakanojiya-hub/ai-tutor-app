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

  // --- YouTube video integration ---
  static String lessonVideos(int lessonId) => '/lessons/$lessonId/videos';
  static String lessonVideoProgress(int lessonId) => '/lessons/$lessonId/videos/progress';
  static const String videoSearch = '/videos/search';

  // --- Quiz & Assessment ---
  static String submitLessonQuizAttempt(int lessonId) => '/quiz/lessons/$lessonId/attempt';
  static const String submitFreeformQuizAttempt = '/quiz/freeform/attempt';
  static const String quizAttempts = '/quiz/attempts';
  static String quizAttempt(int id) => '/quiz/attempts/$id';
  static const String quizAnalytics = '/quiz/analytics';
  static const String quizGenerate = '/quiz/generate';

  // --- Learning Streak ---
  static const String streak = '/streak';

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
