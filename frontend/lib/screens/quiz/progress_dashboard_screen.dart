import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/quiz_attempt_model.dart';
import '../../models/subject_model.dart';
import '../../services/quiz_service.dart';
import '../../services/streak_service.dart';
import '../../services/subject_service.dart';
import '../../widgets/skeleton_box.dart';

/// Full Progress Dashboard: overall progress, real Learning Streak
/// (current + longest + weekly graph), study hours, course-wise progress,
/// quiz performance, a weekly performance trend, a learning calendar
/// heatmap, rule-based achievements, AI insights (strength/weakness from
/// real data, no fabricated "predicted score"), and a composite Learning
/// Health Score built from real signals.
class ProgressDashboardScreen extends StatefulWidget {
  const ProgressDashboardScreen({super.key});

  @override
  State<ProgressDashboardScreen> createState() => _ProgressDashboardScreenState();
}

class _ProgressDashboardScreenState extends State<ProgressDashboardScreen> {
  final SubjectService _subjectService = SubjectService();
  final QuizService _quizService = QuizService();
  final StreakService _streakService = StreakService();

  List<SubjectModel> _subjects = [];
  QuizAnalyticsModel? _analytics;
  StreakSummary? _streak;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _subjects = await _subjectService.fetchAllSubjects();
      _analytics = await _quizService.fetchAnalytics();
      _streak = await _streakService.fetchSummary();
    } catch (e) {
      _error = 'Could not load your progress. Please try again.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  int get _totalLessonsCompleted => _subjects.fold(0, (sum, s) => sum + s.completedLessons);
  int get _totalLessons => _subjects.fold(0, (sum, s) => sum + s.lessonCount);
  double get _totalCompletedHours => _subjects.fold(0.0, (sum, s) => sum + s.completedHours);
  int get _coursesCompleted => _subjects.where((s) => s.progressPercentage >= 100).length;
  double get _overallProgress => _totalLessons == 0 ? 0 : (_totalLessonsCompleted / _totalLessons) * 100;

  List<SubjectModel> get _inProgressSubjects =>
      _subjects.where((s) => s.progressPercentage > 0 && s.progressPercentage < 100).toList()
        ..sort((a, b) => b.progressPercentage.compareTo(a.progressPercentage));

  SubjectAccuracyModel? get _strongestSubject {
    final withAttempts = (_analytics?.bySubject ?? []).where((s) => s.attempts > 0).toList();
    if (withAttempts.isEmpty) return null;
    withAttempts.sort((a, b) => b.accuracy.compareTo(a.accuracy));
    return withAttempts.first;
  }

  SubjectAccuracyModel? get _weakestSubject {
    final withAttempts = (_analytics?.bySubject ?? []).where((s) => s.attempts > 0).toList();
    if (withAttempts.isEmpty) return null;
    withAttempts.sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return withAttempts.first;
  }

  /// Composite score from real signals only (Consistency from streak,
  /// Accuracy from quiz analytics, Engagement from attempt volume). This
  /// is our own defined formula, not a scientific measurement - shown
  /// transparently with its breakdown so it's never mistaken for one.
  Map<String, double> get _healthBreakdown {
    final consistency = ((_streak?.activeDaysThisWeek ?? 0) / 7 * 100).clamp(0.0, 100.0);
    final accuracy = (_analytics?.overallAccuracy ?? 0).clamp(0.0, 100.0);
    final engagement = (((_analytics?.totalAttempts ?? 0) / 20) * 100).clamp(0.0, 100.0);
    return {'Consistency': consistency, 'Accuracy': accuracy, 'Engagement': engagement};
  }

  double get _healthScore {
    final b = _healthBreakdown;
    return (b.values.reduce((a, c) => a + c) / b.length);
  }

  List<_Achievement> get _achievements {
    final longestStreak = _streak?.longestStreak ?? 0;
    final totalAttempts = _analytics?.totalAttempts ?? 0;
    final accuracy = _analytics?.overallAccuracy ?? 0;
    final highest = _analytics?.highestScore ?? 0;
    final activeThisWeek = _streak?.activeDaysThisWeek ?? 0;
    final hasCompletedCourse = _subjects.any((s) => s.progressPercentage >= 100);

    return [
      _Achievement('\u{1F525}', '7 Day Streak', longestStreak >= 7, 'Reach a 7-day streak'),
      _Achievement('\u{1F947}', 'Quiz Master', totalAttempts >= 10 && accuracy >= 80, '10+ quizzes at 80%+ accuracy'),
      _Achievement('\u{1F4DA}', 'Course Champion', hasCompletedCourse, 'Complete any full subject'),
      _Achievement('\u26A1', 'Fast Learner', _totalLessonsCompleted >= 20, 'Complete 20+ lessons'),
      _Achievement('\u{1F3C6}', 'Top Performer', highest >= 100, 'Score 100% on any quiz'),
      _Achievement('\u{1F3AF}', 'Goal Achiever', activeThisWeek >= 7, 'Active all 7 days this week'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Learning Progress'),
        elevation: 0,
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textPrimary,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? _buildSkeleton()
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        SkeletonBox(height: 220, borderRadius: BorderRadius.all(Radius.circular(28))),
        SizedBox(height: 16),
        SkeletonBox(height: 150, borderRadius: BorderRadius.all(Radius.circular(24))),
        SizedBox(height: 16),
        SkeletonBox(height: 200, borderRadius: BorderRadius.all(Radius.circular(24))),
      ],
    );
  }

  Widget _buildError() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry'))),
      ],
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Text('Track your learning journey', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        const SizedBox(height: 20),
        _buildHeroCard(),
        const SizedBox(height: 20),
        _buildStreakCard(),
        const SizedBox(height: 20),
        _buildStudyTimeCard(),
        const SizedBox(height: 28),
        _sectionTitle('Course Progress'),
        const SizedBox(height: 10),
        ..._subjects.where((s) => s.lessonCount > 0).map(_buildCourseCard),
        const SizedBox(height: 28),
        _sectionTitle('Quiz Performance'),
        const SizedBox(height: 10),
        _buildQuizPerformanceCard(),
        const SizedBox(height: 20),
        _buildWeeklyTrendCard(),
        const SizedBox(height: 28),
        _sectionTitle('Learning Calendar'),
        const SizedBox(height: 10),
        _buildHeatmapCard(),
        const SizedBox(height: 28),
        _sectionTitle('Achievements'),
        const SizedBox(height: 10),
        _buildAchievements(),
        const SizedBox(height: 28),
        _sectionTitle('AI Insights'),
        const SizedBox(height: 10),
        _buildAiInsights(),
        const SizedBox(height: 28),
        _sectionTitle('Learning Health Score'),
        const SizedBox(height: 10),
        _buildHealthScoreCard(),
        const SizedBox(height: 28),
        _sectionTitle('Recommended Actions'),
        const SizedBox(height: 10),
        _buildRecommendedActions(),
      ],
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700));

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: [Color(0xFF7C5CFC), Color(0xFFA78BFA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: AppColors.purple.withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _overallProgress / 100),
                      duration: const Duration(milliseconds: 800),
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 7,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    Text('${_overallProgress.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text('Overall Progress', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _heroStat('Courses', '$_coursesCompleted/${_subjects.where((s) => s.lessonCount > 0).length}'),
              _heroStat('Lessons', '$_totalLessonsCompleted'),
              _heroStat('Hours', _totalCompletedHours.toStringAsFixed(1)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push(_inProgressSubjects.isNotEmpty
                  ? '/lessons'
                  : '/categories', extra: _inProgressSubjects.isNotEmpty
                  ? {'subjectId': _inProgressSubjects.first.id, 'subjectName': _inProgressSubjects.first.name}
                  : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.purple,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Continue Learning', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStreakCard() {
    final weekly = _streak?.weeklyActivity ?? List.filled(7, false);
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('\u{1F525} Learning Streak', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              Text(_streak?.currentStreak == 0 ? 'Start today!' : "You're doing great!", style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _streakStat('Current', '${_streak?.currentStreak ?? 0} Days', AppColors.purple),
              const SizedBox(width: 20),
              _streakStat('Longest', '${_streak?.longestStreak ?? 0} Days', AppColors.orange),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final active = i < weekly.length && weekly[i];
              return Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: active ? AppColors.purple : AppColors.pageBackground,
                      shape: BoxShape.circle,
                    ),
                    child: active ? const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 15) : null,
                  ),
                  const SizedBox(height: 4),
                  Text(dayLabels[i], style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _streakStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildStudyTimeCard() {
    return _whiteCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.access_time_filled_rounded, color: AppColors.orange),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Study Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text('${_totalCompletedHours.toStringAsFixed(1)} hours across completed lessons', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard(SubjectModel s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _whiteCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.purple.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.menu_book_rounded, color: AppColors.purple),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${s.completedLessons}/${s.lessonCount} lessons', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (s.progressPercentage / 100).clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: AppColors.purple.withOpacity(0.12),
                      valueColor: const AlwaysStoppedAnimation(AppColors.purple),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('${s.progressPercentage.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.purple)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizPerformanceCard() {
    final a = _analytics;
    return _whiteCard(
      child: Column(
        children: [
          Row(
            children: [
              _quizStat('${a?.totalAttempts ?? 0}', 'Attempted', AppColors.blue),
              _quizStat('${a?.passedCount ?? 0}', 'Passed', AppColors.green),
              _quizStat('${a?.failedCount ?? 0}', 'Failed', AppColors.error),
            ],
          ),
          const Divider(height: 28),
          Row(
            children: [
              _quizStat('${a?.averageScore.toStringAsFixed(0) ?? 0}%', 'Average', AppColors.purple),
              _quizStat('${a?.highestScore ?? 0}%', 'Highest', AppColors.orange),
              _quizStat('${a?.overallAccuracy.toStringAsFixed(0) ?? 0}%', 'Accuracy', AppColors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quizStat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildWeeklyTrendCard() {
    final trend = _analytics?.weeklyTrend ?? [];
    if (trend.isEmpty) return const SizedBox.shrink();

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This Week\'s Accuracy', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 16),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: trend.map((d) {
                final label = d.date.length >= 10 ? d.date.substring(8, 10) : d.date;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(d.attempts > 0 ? '${d.accuracy.toStringAsFixed(0)}' : '-', style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: d.attempts > 0 ? (d.accuracy / 100).clamp(0.05, 1) : 0.02),
                          duration: const Duration(milliseconds: 600),
                          builder: (context, value, _) => Container(
                            height: 50 * value,
                            decoration: BoxDecoration(
                              color: d.attempts > 0 ? AppColors.purple : AppColors.purpleLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapCard() {
    final days = _streak?.heatmap ?? [];
    if (days.isEmpty) return const SizedBox.shrink();

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Last 35 days', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: days
                .map((d) => Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: d.active ? AppColors.purple : AppColors.pageBackground,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievements() {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _achievements.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final a = _achievements[index];
          return Container(
            width: 110,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: a.unlocked ? AppColors.purpleLight : AppColors.card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppTheme.softShadow,
              border: a.unlocked ? null : Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(opacity: a.unlocked ? 1 : 0.35, child: Text(a.emoji, style: const TextStyle(fontSize: 26))),
                const Spacer(),
                Text(a.title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: a.unlocked ? AppColors.purple : AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (!a.unlocked) Text(a.hint, style: const TextStyle(fontSize: 8, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAiInsights() {
    final strength = _strongestSubject;
    final weakness = _weakestSubject;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('\u{1F916} AI Learning Insights', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 14),
          if (strength == null && weakness == null)
            const Text('Take a few quizzes to unlock personalized insights.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
          else ...[
            if (strength != null) _insightRow('Strength', strength.subjectName, AppColors.green),
            if (weakness != null) _insightRow('Needs Improvement', weakness.subjectName, AppColors.error),
            if (weakness != null) ...[
              const SizedBox(height: 10),
              Text('Recommendation: Practice more ${weakness.subjectName} quizzes to raise your accuracy above 60%.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _insightRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildHealthScoreCard() {
    final breakdown = _healthBreakdown;
    return _whiteCard(
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _healthScore / 100),
                  duration: const Duration(milliseconds: 800),
                  builder: (context, value, _) => CircularProgressIndicator(
                    value: value,
                    strokeWidth: 8,
                    backgroundColor: AppColors.purpleLight,
                    valueColor: const AlwaysStoppedAnimation(AppColors.purple),
                  ),
                ),
                Text('${_healthScore.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: breakdown.entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            SizedBox(width: 90, child: Text(e.key, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(value: e.value / 100, minHeight: 6, backgroundColor: AppColors.purpleLight, valueColor: const AlwaysStoppedAnimation(AppColors.purple)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('${e.value.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedActions() {
    final actions = <_ActionItem>[];
    if (_inProgressSubjects.isNotEmpty) {
      final s = _inProgressSubjects.first;
      actions.add(_ActionItem(Icons.play_circle_rounded, 'Continue ${s.name}', AppColors.purple, () => context.push('/lessons', extra: {'subjectId': s.id, 'subjectName': s.name})));
    }
    final weakness = _weakestSubject;
    if (weakness != null) {
      actions.add(_ActionItem(Icons.quiz_rounded, 'Practice ${weakness.subjectName} Quiz', AppColors.blue, () => context.push('/ai-quiz-generator')));
    }
    actions.add(_ActionItem(Icons.smart_toy_rounded, 'Ask AI Tutor a Question', AppColors.orange, () => context.push('/ai-tutor')));
    actions.add(_ActionItem(Icons.explore_rounded, 'Browse New Courses', AppColors.green, () => context.push('/categories')));

    return Column(
      children: actions
          .map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: a.onTap,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
                      child: Row(
                        children: [
                          Icon(a.icon, color: a.color, size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _whiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(22), boxShadow: AppTheme.softShadow),
      child: child,
    );
  }
}

class _Achievement {
  final String emoji;
  final String title;
  final bool unlocked;
  final String hint;
  _Achievement(this.emoji, this.title, this.unlocked, this.hint);
}

class _ActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _ActionItem(this.icon, this.label, this.color, this.onTap);
}
