/// Centralized API configuration so base URLs and endpoint paths
/// only ever need to change in one place.
class ApiConstants {
  ApiConstants._();

  /// Android emulator maps 10.0.2.2 to the host machine's localhost.
  /// - Physical device / real backend: replace with your machine's LAN IP
  ///   or your deployed Render URL, e.g. https://your-app.onrender.com
  /// - iOS simulator: use http://localhost:8080
  static const String baseUrl = 'http://192.168.1.27:8080/api';

  // --- Day 1: Auth ---
  static const String register = '/auth/register';
  static const String badgesMine = '/badges/mine';
  static String badgesForStudent(int studentId) => '/badges/student/$studentId';
  static const String xpMine = '/xp/mine';
  static String leaderboard({String period = 'overall', String? classFilter, String? section}) {
    var path = '/leaderboard?period=$period';
    if (classFilter != null && classFilter.isNotEmpty) path += '&class=$classFilter';
    if (section != null && section.isNotEmpty) path += '&section=$section';
    return path;
  }
  static String assignClassSection(int studentId) => '/admin/students/$studentId/class-section';
  static const String adminStudents = '/admin/students';
  static const String certificatesMine = '/certificates/mine';
  static const String certificatesTeacher = '/certificates/teacher';
  static const String certificatesAll = '/certificates/all';
  static String certificate(int id) => '/certificates/$id';
  static const String teacherApply = '/auth/teacher/apply';
  static const String login = '/auth/login';
  static const String profile = '/auth/profile';
  static const String updateProfile = '/users/profile';
  static const String changePassword = '/users/change-password';

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

  // --- Admin Panel ---
  static const String adminDashboard = '/admin/dashboard';
  static const String adminPendingTeachers = '/auth/admin/teachers/pending';
  static String adminApproveTeacher(int id) => '/auth/admin/teachers/$id/approve';
  static String adminRejectTeacher(int id) => '/auth/admin/teachers/$id/reject';

  // --- Assignments ---
  static const String assignments = '/assignments';
  static String assignment(int id) => '/assignments/$id';
  static String assignmentPublish(int id) => '/assignments/$id/publish';
  static String assignmentUnpublish(int id) => '/assignments/$id/unpublish';
  static String assignmentClose(int id) => '/assignments/$id/close';
  static String assignmentArchive(int id) => '/assignments/$id/archive';
  static const String assignmentGenerateAI = '/assignments/generate-ai';
  static const String myAssignments = '/assignments/mine';
  static const String teacherAssignmentAnalytics = '/assignments/analytics';
  static String assignmentSubmissions(int id) => '/assignments/$id/submissions';
  static String reviewSubmission(int id) => '/assignments/submissions/$id/review';
  static String assignmentDraft(int id) => '/assignments/$id/draft';
  static String assignmentSubmit(int id) => '/assignments/$id/submit';
  static String mySubmission(int id) => '/assignments/$id/my-submission';
  static String retryEvaluation(int submissionId) => '/assignments/submissions/$submissionId/retry-evaluation';
  static const String assignmentsForStudent = '/assignments/for-student';
  static String subjectAssignments(int subjectId) => '/subjects/$subjectId/assignments';
  static const String adminAssignments = '/admin/assignments';
  static const String adminAssignmentAnalytics = '/admin/assignments/analytics';

  // --- Live Classes (Phase 1: scheduling only, no video) ---
  static const String liveClasses = '/live-classes';
  static String liveClass(int id) => '/live-classes/$id';
  static String liveClassCancel(int id) => '/live-classes/$id/cancel';
  static String liveClassComplete(int id) => '/live-classes/$id/complete';
  static const String myLiveClasses = '/live-classes/mine';
  static const String liveClassesForStudent = '/live-classes/for-student';
  static const String adminLiveClasses = '/admin/live-classes';
  static String adminLiveClassCancel(int id) => '/admin/live-classes/$id/cancel';
  static String liveClassCheckIn(int id) => '/live-classes/$id/check-in';
  static String liveClassMyAttendance(int id) => '/live-classes/$id/my-attendance';
  static String liveClassAttendance(int id) => '/live-classes/$id/attendance';
  static const String liveClassAttendanceSummary = '/live-classes/attendance-summary';
  static String liveClassStart(int id) => '/live-classes/$id/start';
  static String liveClassJoin(int id) => '/live-classes/$id/join';
  static String liveClassEnd(int id) => '/live-classes/$id/end';
  static String liveClassMeetingStatus(int id) => '/live-classes/$id/meeting-status';
  static String liveClassResources(int id) => '/live-classes/$id/resources';
  static String liveClassResourceDelete(int classId, int resourceId) => '/live-classes/$classId/resources/$resourceId';
  static String liveClassMute(int id, String identity) => '/live-classes/$id/mute/$identity';
  static String liveClassRemove(int id, String identity) => '/live-classes/$id/remove/$identity';
  static String liveClassMuteAll(int id) => '/live-classes/$id/mute-all';
  static String liveClassLock(int id) => '/live-classes/$id/lock';
  static String liveClassUnlock(int id) => '/live-classes/$id/unlock';

  // --- Notifications ---
  static const String notifications = '/notifications';
  static const String notificationUnreadCount = '/notifications/unread-count';
  static String notificationRead(int id) => '/notifications/$id/read';
  static const String notificationReadAll = '/notifications/read-all';

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
