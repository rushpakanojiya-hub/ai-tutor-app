import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/quiz_attempt_model.dart';
import '../../services/quiz_service.dart';
import '../../widgets/skeleton_box.dart';

/// Shows quiz performance analytics computed from the student's real
/// attempt history: overall accuracy, per-subject accuracy, and weak
/// topics (subjects averaging under 60% accuracy).
class QuizAnalyticsScreen extends StatefulWidget {
  const QuizAnalyticsScreen({super.key});

  @override
  State<QuizAnalyticsScreen> createState() => _QuizAnalyticsScreenState();
}

class _QuizAnalyticsScreenState extends State<QuizAnalyticsScreen> {
  final QuizService _quizService = QuizService();

  QuizAnalyticsModel? _analytics;
  List<QuizAttemptSummary> _history = [];
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
      final results = await Future.wait([
        _quizService.fetchAnalytics(),
        _quizService.fetchAttempts(),
      ]);
      _analytics = results[0] as QuizAnalyticsModel;
      _history = results[1] as List<QuizAttemptSummary>;
    } catch (e) {
      _error = 'Could not load analytics. Please try again.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Quiz Analytics')),
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
      children: [
        const SkeletonBox(height: 100, borderRadius: BorderRadius.all(Radius.circular(20))),
        const SizedBox(height: 16),
        const SkeletonBox(height: 200, borderRadius: BorderRadius.all(Radius.circular(20))),
      ],
    );
  }

  Widget _buildError() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry'))),
      ],
    );
  }

  Widget _buildContent() {
    final analytics = _analytics!;

    if (analytics.totalAttempts == 0) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Icon(Icons.bar_chart_rounded, size: 48, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Center(
            child: Text('No quiz attempts yet.', style: TextStyle(color: AppColors.textSecondary)),
          ),
          SizedBox(height: 4),
          Center(
            child: Text(
              'Take a quiz on any lesson, or try the AI Quiz Generator!',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _overallCard(analytics),
        const SizedBox(height: 20),
        if (analytics.weakTopics.isNotEmpty) ...[
          const Text('Weak Topics', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          ...analytics.weakTopics.map(_weakTopicTile),
          const SizedBox(height: 20),
        ],
        const Text('By Subject', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 10),
        ...analytics.bySubject.map(_subjectAccuracyTile),
        const SizedBox(height: 20),
        const Text('Recent Attempts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 10),
        ..._history.take(10).map(_historyTile),
      ],
    );
  }

  Widget _overallCard(QuizAnalyticsModel analytics) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.purple,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Overall Accuracy', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            '${analytics.overallAccuracy.toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '${analytics.totalAttempts} quiz attempt${analytics.totalAttempts == 1 ? '' : 's'} so far',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _weakTopicTile(SubjectAccuracyModel s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE8E6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_down_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.subjectName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          Text('${s.accuracy.toStringAsFixed(0)}%', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _subjectAccuracyTile(SubjectAccuracyModel s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(s.subjectName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text('${s.accuracy.toStringAsFixed(0)}% (${s.attempts} attempt${s.attempts == 1 ? '' : 's'})',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (s.accuracy / 100).clamp(0, 1),
              minHeight: 6,
              backgroundColor: AppColors.purpleLight,
              valueColor: AlwaysStoppedAnimation(s.accuracy < 60 ? AppColors.error : AppColors.purple),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(QuizAttemptSummary attempt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: attempt.scorePercent >= 60 ? AppColors.greenLight : const Color(0xFFFDE8E6),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${attempt.scorePercent}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: attempt.scorePercent >= 60 ? AppColors.green : AppColors.error,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              attempt.topic.isNotEmpty ? attempt.topic : 'Lesson Quiz',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Text('${attempt.correctCount}/${attempt.totalQuestions}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
