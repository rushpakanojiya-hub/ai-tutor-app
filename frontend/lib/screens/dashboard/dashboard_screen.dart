import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/assignment_model.dart';
import '../../models/recommendation.dart';
import '../../models/subject_model.dart';
import '../../providers/ai_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/assignment_service.dart';
import '../../services/notification_service.dart';
import '../../services/quiz_service.dart';
import '../../services/streak_service.dart';
import '../../services/subject_service.dart';
import '../ai/ai_tutor_screen.dart';
import '../assignments/student_assignments_screen.dart';
import '../categories/categories_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/skeleton_box.dart';

/// Student dashboard shell: 5 tabs (Home, Courses, Assignments, AI Tutor,
/// Profile). The AI Quiz Generator quick-launch lives on the Home
/// dashboard's own Quiz card and in Profile - no separate floating
/// button needed once Assignments has a proper tab.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  List<Widget> _pages(bool isStudent) => [
        const _DashboardHome(),
        const CategoriesScreen(),
        if (isStudent) const StudentAssignmentsScreen(),
        const AiTutorScreen(),
        const ProfileScreen(),
      ];

  Widget _navItem(int index, IconData outlined, IconData filled, String label) {
    final selected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? filled : outlined, color: selected ? AppColors.purple : AppColors.textSecondary, size: 22),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10, color: selected ? AppColors.purple : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStudent = context.watch<AuthProvider>().currentUser?.role == 'student';
    final pages = _pages(isStudent);
    if (_currentIndex >= pages.length) _currentIndex = 0;

    return PopScope(
      // Only governs this root bottom-nav shell. Nested pages pushed via
      // Navigator (Edit Profile, a Lesson, AI Tutor Chat, an Assignment,
      // etc.) are unaffected - they still pop normally since PopScope
      // only intercepts back on THIS route, not routes pushed on top of it.
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return; // already on Home - let the app exit normally
        setState(() => _currentIndex = 0);
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBackground,
        body: SafeArea(child: pages[_currentIndex]),
        bottomNavigationBar: Container(
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.card,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -4))],
          ),
          child: Row(
            children: [
              _navItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
              _navItem(1, Icons.menu_book_outlined, Icons.menu_book_rounded, 'Courses'),
              if (isStudent) _navItem(2, Icons.assignment_outlined, Icons.assignment_rounded, 'Assignments'),
              _navItem(isStudent ? 3 : 2, Icons.smart_toy_outlined, Icons.smart_toy_rounded, 'AI Tutor'),
              _navItem(isStudent ? 4 : 3, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
            ],
          ),
        ),
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
  final SubjectService _subjectService = SubjectService();
  final QuizService _quizService = QuizService();
  final StreakService _streakService = StreakService();
  final AssignmentService _assignmentService = AssignmentService();
  final NotificationService _notificationService = NotificationService();

  List<SubjectModel> _subjects = [];
  int _totalAttempts = 0;
  double _accuracy = 0;
  StreakSummary? _streak;
  List<AssignmentModel> _pendingAssignments = [];
  int _unreadNotifications = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _subjects = await _subjectService.fetchAllSubjects();
    } catch (_) {}
    try {
      final analytics = await _quizService.fetchAnalytics();
      _totalAttempts = analytics.totalAttempts;
      _accuracy = analytics.overallAccuracy;
    } catch (_) {}
    try {
      _streak = await _streakService.fetchSummary();
    } catch (_) {}
    try {
      _unreadNotifications = await _notificationService.fetchUnreadCount();
    } catch (_) {}
    // QA fix ("Missing mounted checks after async operations"): this
    // context.read<AuthProvider>() ran after several awaits above with
    // no mounted guard - if the user had navigated away mid-fetch, this
    // threw on a deactivated widget's context.
    if (!mounted) return;
    if (context.read<AuthProvider>().currentUser?.role == 'student') {
      try {
        _pendingAssignments = (await _assignmentService.fetchForStudent())
            .where((a) => a.myStatus == 'not_started' || a.myStatus == 'draft')
            .toList();
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _isLoading = false);
      context.read<AiProvider>().loadRecommendations();
    }
  }

  int get _totalLessonsCompleted => _subjects.fold(0, (sum, s) => sum + s.completedLessons);
  double get _totalStudyHours => _subjects.fold(0.0, (sum, s) => sum + s.learningHours);

  List<SubjectModel> get _inProgressSubjects =>
      _subjects.where((s) => s.progressPercentage > 0 && s.progressPercentage < 100).toList()
        ..sort((a, b) => b.progressPercentage.compareTo(a.progressPercentage));

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final recommendations = context.watch<AiProvider>().recommendations;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
        children: [
          _buildHeader(user?.name ?? 'Student'),
          const SizedBox(height: 24),
          _buildSearchBar(),
          const SizedBox(height: 24),
          if (_pendingAssignments.isNotEmpty) ...[
            _sectionHeader('New Assignments', onSeeAll: () => context.push('/assignment-detail', extra: {'assignmentId': _pendingAssignments.first.id})),
            const SizedBox(height: 12),
            ..._pendingAssignments.take(2).map(_buildAssignmentCard),
            const SizedBox(height: 20),
          ],
          _buildQuickAccessGrid(),
          const SizedBox(height: 32),
          _buildStreakHero(),
          const SizedBox(height: 32),
          _sectionHeader('Continue Learning', onSeeAll: () => context.push('/categories')),
          const SizedBox(height: 12),
          _buildContinueLearning(),
          const SizedBox(height: 32),
          _sectionHeader('Your Stats', onSeeAll: () => context.push('/quiz-analytics')),
          const SizedBox(height: 12),
          _buildStatsGrid(),
          const SizedBox(height: 32),
          _sectionHeader('Recommended for You', onSeeAll: () => context.push('/ai-tutor')),
          const SizedBox(height: 12),
          _buildRecommendations(recommendations),
        ],
      ),
    );
  }

  Widget _buildHeader(String name) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $name \u{1F44B}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.2),
              ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 8),
              const Text(
                'Ready to continue your learning journey?',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ).animate().fadeIn(duration: 220.ms, delay: 80.ms),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: AppColors.card,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () async {
              await context.push('/notifications');
              if (mounted) _load();
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: AppTheme.softShadow),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
                  if (_unreadNotifications > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.purpleLight,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: AppTheme.softShadow,
          ),
          child: Center(
            child: Text(
              (name.isNotEmpty ? name[0] : '?').toUpperCase(),
              style: const TextStyle(fontSize: 20, color: AppColors.purple, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssignmentCard(AssignmentModel a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/assignment-detail', extra: {'assignmentId': a.id}),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.assignment_rounded, color: AppColors.purple, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${a.subjectName} \u2022 ${a.teacherName}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (a.dueDate != null)
                      _pill(Icons.event_outlined, 'Due ${a.dueDate!.day}/${a.dueDate!.month}'),
                    _pill(Icons.grade_outlined, '${a.maxMarks} marks'),
                    _pill(Icons.speed_outlined, a.difficulty),
                    if (a.estimatedMinutes != null) _pill(Icons.timer_outlined, '${a.estimatedMinutes} min'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.push('/assignment-detail', extra: {'assignmentId': a.id}),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
                    child: const Text('Start Assignment'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.pageBackground, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.push('/search'),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: AppTheme.softShadow),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.textSecondary),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search for courses, topics or skills...',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 220.ms, delay: 60.ms);
  }

  /// 2x2 grid (not a cramped 4-in-a-row) so titles/subtitles never overflow.
  Widget _buildQuickAccessGrid() {
    final cards = [
      _QuickAccessData(Icons.menu_book_rounded, 'My Courses', 'Continue learning', const Color(0xFF6D5DF6), const Color(0xFF5B4CF0), () => context.push('/categories')),
      _QuickAccessData(Icons.smart_toy_rounded, 'AI Tutor', 'Ask anything', const Color(0xFFFF7A18), const Color(0xFFFF5A3D), () => context.push('/ai-tutor')),
      _QuickAccessData(Icons.help_outline_rounded, 'Quiz', 'Test your knowledge', const Color(0xFF3B82F6), const Color(0xFF2563EB), () => context.push('/ai-quiz-generator')),
      _QuickAccessData(Icons.trending_up_rounded, 'Progress', 'Track your growth', const Color(0xFF22C55E), const Color(0xFF16A34A), () => context.push('/quiz-analytics')),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 170 / 150,
      children: [
        for (var i = 0; i < cards.length; i++)
          _QuickAccessCard(data: cards[i]).animate().fadeIn(duration: 220.ms, delay: (100 + i * 60).ms).slideY(begin: 0.15, end: 0),
      ],
    );
  }

  Widget _buildStreakHero() {
    final streakCount = _streak?.currentStreak ?? 0;
    final weekCount = _streak?.activeDaysThisWeek ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: [Color(0xFF7C5CFF), Color(0xFF5B3DF5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: const Color(0xFF5B3DF5).withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Learning Streak \u{1F525}', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _isLoading
                    ? const SizedBox(height: 40, width: 40, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('$streakCount', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 6),
                          const Text('Days', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                const SizedBox(height: 8),
                Text(
                  streakCount > 0 ? "Keep it up! You're doing great." : 'Complete a lesson or quiz today to start your streak!',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text('$weekCount/7 active days this week', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 56),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms, delay: 300.ms).scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1));
  }

  Widget _sectionHeader(String title, {required VoidCallback onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
        TextButton(onPressed: onSeeAll, child: const Text('See all')),
      ],
    );
  }

  Widget _buildContinueLearning() {
    if (_isLoading) {
      return Column(
        children: List.generate(
          2,
          (_) => const Padding(padding: EdgeInsets.only(bottom: 10), child: SkeletonBox(height: 90, borderRadius: BorderRadius.all(Radius.circular(20)))),
        ),
      );
    }

    final inProgress = _inProgressSubjects.take(3).toList();

    if (inProgress.isEmpty) {
      return Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/categories'),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
            child: const Row(
              children: [
                Icon(Icons.explore_outlined, color: AppColors.purple),
                SizedBox(width: 12),
                Expanded(child: Text("You haven't started a course yet. Tap to browse subjects!", style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: inProgress
          .map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ContinueLearningCard(
                title: s.name,
                meta: '${s.completedLessons}/${s.lessonCount} lessons \u2022 ${s.progressPercentage.toStringAsFixed(0)}%',
                progress: s.progressPercentage / 100,
                onTap: () => context.push('/lessons', extra: {'subjectId': s.id, 'subjectName': s.name}),
              ),
            ),
          )
          .toList(),
    ).animate().fadeIn(duration: 220.ms, delay: 340.ms);
  }

  Widget _buildStatsGrid() {
    final stats = [
      _StatData(Icons.menu_book_rounded, '$_totalLessonsCompleted', 'Lessons\nCompleted', AppColors.purple, AppColors.purpleLight),
      _StatData(Icons.quiz_rounded, '$_totalAttempts', 'Quizzes\nAttempted', AppColors.blue, AppColors.blueLight),
      _StatData(Icons.track_changes_rounded, '${_accuracy.toStringAsFixed(0)}%', 'Accuracy\nAverage', AppColors.green, AppColors.greenLight),
      _StatData(Icons.access_time_filled_rounded, _totalStudyHours.toStringAsFixed(1), 'Study\nHours', AppColors.orange, AppColors.orangeLight),
      _StatData(Icons.local_fire_department_rounded, '${_streak?.activeDaysThisWeek ?? 0}/7', 'Weekly\nStreak', const Color(0xFFE84C61), const Color(0xFFFDE8EC)),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1,
      children: stats.map((s) => _StatCard(data: s)).toList(),
    );
  }

  Widget _buildRecommendations(List<RecommendationModel> recommendations) {
    if (recommendations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Complete a few lessons to get personalized recommendations!', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      );
    }

    final palette = [
      (AppColors.purpleLight, AppColors.purple),
      (AppColors.orangeLight, AppColors.orange),
      (AppColors.greenLight, AppColors.green),
      (AppColors.blueLight, AppColors.blue),
    ];

    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recommendations.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final rec = recommendations[index];
          final colors = palette[index % palette.length];
          return _RecommendedCard(
            title: rec.recommendedTitle,
            subject: rec.subjectName,
            bg: colors.$1,
            fg: colors.$2,
            onTap: () => context.push('/lesson-player', extra: {'lessonId': rec.recommendedLessonId}),
          );
        },
      ),
    );
  }
}

class _QuickAccessData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color gradientStart;
  final Color gradientEnd;
  final VoidCallback onTap;
  _QuickAccessData(this.icon, this.title, this.subtitle, this.gradientStart, this.gradientEnd, this.onTap);
}

class _QuickAccessCard extends StatelessWidget {
  final _QuickAccessData data;
  const _QuickAccessCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(colors: [data.gradientStart, data.gradientEnd], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: data.gradientEnd.withOpacity(0.28), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: data.onTap,
          splashColor: Colors.white.withOpacity(0.15),
          highlightColor: Colors.white.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                  child: Icon(data.icon, color: Colors.white, size: 22),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(data.subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(Icons.arrow_forward_rounded, color: data.gradientStart, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueLearningCard extends StatelessWidget {
  final String title;
  final String meta;
  final double progress;
  final VoidCallback? onTap;

  const _ContinueLearningCard({required this.title, required this.meta, required this.progress, this.onTap});

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
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.purple.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.menu_book_rounded, color: AppColors.purple, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(meta, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: progress.clamp(0, 1)),
                        duration: const Duration(milliseconds: 600),
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: AppColors.purple.withOpacity(0.12),
                          valueColor: const AlwaysStoppedAnimation(AppColors.purple),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: AppColors.purple, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color bg;
  _StatData(this.icon, this.value, this.label, this.color, this.bg);
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: data.bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(data.icon, color: data.color, size: 16),
          ),
          const SizedBox(height: 6),
          FittedBox(child: Text(data.value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          const SizedBox(height: 2),
          Text(data.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary, height: 1.2)),
        ],
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final String title;
  final String subject;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _RecommendedCard({required this.title, required this.subject, required this.bg, required this.fg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 170,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
              ),
              const Spacer(),
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(subject, style: TextStyle(fontSize: 11, color: fg.withOpacity(0.8)), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
