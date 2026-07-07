import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/lesson_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/lesson_card.dart';
import '../../widgets/skeleton_box.dart';

/// Feature 3: ordered list of lessons within a subject, each showing a
/// completion checkmark backed by real, persisted progress
/// (see LessonProvider.loadLessons).
class LessonsScreen extends StatefulWidget {
  final int subjectId;
  final String subjectName;

  const LessonsScreen({super.key, required this.subjectId, required this.subjectName});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<LessonProvider>().loadLessons(widget.subjectId);
      // Remembers the most recently opened subject locally, so the
      // Dashboard's "Continue Learning" section can show real progress
      // for it (see dashboard_screen.dart). No backend schema change â€”
      // just SharedPreferences via the existing StorageService.
      await _storage.setInt(AppConstants.keyLastSubjectId, widget.subjectId);
      await _storage.setString(AppConstants.keyLastSubjectName, widget.subjectName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LessonProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subjectName),
        actions: [
          if (context.watch<AuthProvider>().currentUser?.role == 'student')
            IconButton(
              tooltip: 'Assignments',
              icon: const Icon(Icons.assignment_rounded),
              onPressed: () => context.push('/subject-assignments', extra: {'subjectId': widget.subjectId, 'subjectName': widget.subjectName}),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.loadLessons(widget.subjectId),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(provider),
        ),
      ),
    );
  }

  Widget _buildBody(LessonProvider provider) {
    if (provider.isLoading) {
      return ListView.separated(
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => SkeletonBox(height: 64, borderRadius: BorderRadius.circular(18)),
      );
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(provider.errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => provider.loadLessons(widget.subjectId), child: const Text('Retry')),
          ],
        ),
      );
    }

    if (provider.lessons.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_lesson_outlined, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('No lessons in this subject yet.', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final progress = provider.subjectProgress;

    return ListView(
      children: [
        if (progress != null && progress.totalLessons > 0) ...[
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Your progress', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(
                      '${progress.completedLessons} of ${progress.totalLessons} complete',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress.percentage,
                    minHeight: 8,
                    backgroundColor: AppColors.purpleLight,
                    valueColor: const AlwaysStoppedAnimation(AppColors.purple),
                  ),
                ),
              ],
            ),
          ),
        ],
        ...provider.lessons.map(
          (lesson) => LessonCard(
            lesson: lesson,
            onTap: () => context.push('/lesson-player', extra: {'lessonId': lesson.id}),
          ),
        ),
      ],
    );
  }
}
