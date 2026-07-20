import 'package:go_router/go_router.dart';
import '../../models/ai_content_model.dart';
import '../../models/quiz_attempt_model.dart';
import '../../providers/auth_provider.dart';
import '../../screens/ai/ai_tutor_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/teacher_apply_screen.dart';
import '../../screens/categories/categories_screen.dart';
import '../../screens/dashboard/dashboard_screen.dart';
import '../../screens/lessons/lesson_player_screen.dart';
import '../../screens/lessons/lessons_screen.dart';
import '../../screens/lessons/pdf_viewer_screen.dart';
import '../../screens/lessons/quiz_screen.dart';
import '../../screens/quiz/ai_quiz_generator_screen.dart';
import '../../screens/quiz/progress_dashboard_screen.dart';
import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/admin/teacher_applications_screen.dart';
import '../../screens/admin/admin_assignments_screen.dart';
import '../../screens/assignments/create_assignment_screen.dart';
import '../../screens/assignments/my_assignments_screen.dart';
import '../../screens/assignments/submission_review_screen.dart';
import '../../screens/assignments/assignment_list_screen.dart';
import '../../screens/assignments/assignment_detail_screen.dart';
import '../../screens/liveclass/create_live_class_screen.dart';
import '../../screens/liveclass/my_live_classes_screen.dart';
import '../../screens/liveclass/student_live_classes_screen.dart';
import '../../screens/liveclass/admin_live_classes_screen.dart';
import '../../screens/notifications/notification_center_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/splash/splash_screen.dart';
import '../../screens/subjects/subjects_screen.dart';

/// Centralized GoRouter config with a redirect guard: unauthenticated users
/// are bounced to /login, authenticated users away from /login /register.
///
/// Day 2 routes (categories/subjects/lessons/player/pdf-viewer/search) all
/// sit "on top of" the authenticated area - none are reachable from
/// /login or /register, matching the Dashboard -> Categories -> ... flow.
class AppRouter {
  final AuthProvider authProvider;

  AppRouter(this.authProvider);

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    // QA fix ("Router rebuild issue"): was `refreshListenable:
    // authProvider` - every notifyListeners() on AuthProvider (including
    // ones only toggling a loading spinner, unrelated to auth status)
    // triggered a full router redirect re-evaluation. statusNotifier
    // only fires when authProvider.status itself actually changes.
    refreshListenable: authProvider.statusNotifier,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/teacher-apply', builder: (context, state) => const TeacherApplyScreen()),
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
            lessonId: extra['lessonId'] as int?,
            subjectId: extra['subjectId'] as int?,
            topic: extra['topic'] as String?,
            quizSessionId: extra['quizSessionId'] as String?,
            questions: (extra['questions'] as List<dynamic>? ?? []).cast<QuizQuestionModel>(),
            freeformQuestions: (extra['freeformQuestions'] as List<dynamic>?)?.cast<QuizAttemptQuestion>(),
          );
        },
      ),
      GoRoute(
        path: '/ai-quiz-generator',
        builder: (context, state) => const AiQuizGeneratorScreen(),
      ),
      GoRoute(
        path: '/quiz-analytics',
        builder: (context, state) => const ProgressDashboardScreen(),
      ),
      GoRoute(
        path: '/admin-dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin-teacher-applications',
        builder: (context, state) => const TeacherApplicationsScreen(),
      ),
      GoRoute(
        path: '/admin-assignments',
        builder: (context, state) => const AdminAssignmentsScreen(),
      ),
      GoRoute(
        path: '/create-assignment',
        builder: (context, state) => const CreateAssignmentScreen(),
      ),
      GoRoute(
        path: '/my-assignments',
        builder: (context, state) => const MyAssignmentsScreen(),
      ),
      GoRoute(
        path: '/assignment-submissions',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          // QA fix ("Fix route parameter null crashes"): was `as int`
          // with no fallback - if extra didn't contain assignmentId (a
          // stale deep link, a caller forgetting to pass extra, etc.)
          // this threw a null-cast exception and crashed the app. Now
          // consistent with every other route in this file.
          return SubmissionReviewScreen(
            assignmentId: extra['assignmentId'] as int? ?? 0,
            title: extra['title'] as String? ?? 'Assignment',
          );
        },
      ),
      GoRoute(
        path: '/subject-assignments',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          // QA fix - same as above.
          return AssignmentListScreen(
            subjectId: extra['subjectId'] as int? ?? 0,
            subjectName: extra['subjectName'] as String? ?? 'Subject',
          );
        },
      ),
      GoRoute(
        path: '/assignment-detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          // QA fix - same as above.
          return AssignmentDetailScreen(assignmentId: extra['assignmentId'] as int? ?? 0);
        },
      ),
      GoRoute(
        path: '/create-live-class',
        builder: (context, state) => const CreateLiveClassScreen(),
      ),
      GoRoute(
        path: '/my-live-classes',
        builder: (context, state) => const MyLiveClassesScreen(),
      ),
      GoRoute(
        path: '/student-live-classes',
        builder: (context, state) => const StudentLiveClassesScreen(),
      ),
      GoRoute(
        path: '/admin-live-classes',
        builder: (context, state) => const AdminLiveClassesScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationCenterScreen(),
      ),

      // --- AI Tutor: single ChatGPT-style screen (chat + history drawer +
      // recommendations + homework mode, all in one) ---
      GoRoute(path: '/ai-tutor', builder: (context, state) => const AiTutorScreen()),
    ],
    // Routing fix ("Invalid Routes"): GoRouter's default error screen for
    // an unknown path is a bare, unstyled error page. This redirects any
    // unmatched route straight to the dashboard instead of showing that.
    errorBuilder: (context, state) => const DashboardScreen(),
    redirect: (context, state) {
      final status = authProvider.status;
      final loggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/teacher-apply';
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

      // Routing fix ("Role-based Routing"): admin-only and teacher-only
      // routes previously had no guard at the router level at all - only
      // the Profile screen's conditional tiles kept most users from ever
      // tapping into them, but a stray deep link or button reaching one
      // directly (e.g. a student navigating to /admin-dashboard) would
      // land them on a real screen that then just failed its admin-only
      // API calls with 403s, instead of being redirected cleanly.
      final role = authProvider.currentUser?.role;
      final isAdminRoute = state.matchedLocation.startsWith('/admin-');
      if (isAdminRoute && role != 'admin') {
        return '/dashboard';
      }
      const teacherOnlyRoutes = {'/create-assignment', '/create-live-class'};
      if (teacherOnlyRoutes.contains(state.matchedLocation) && role != 'teacher' && role != 'admin') {
        return '/dashboard';
      }

      return null;
    },
  );
}
