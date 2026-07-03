import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/lesson_provider.dart';
import '../../widgets/lesson_card.dart';
import '../../widgets/skeleton_box.dart';

/// Feature 3: ordered list of lessons within a subject, each showing a
/// completion checkmark (âœ“ / â¬œ, see LessonModel.isCompleted).
class LessonsScreen extends StatefulWidget {
  final int subjectId;
  final String subjectName;

  const LessonsScreen({super.key, required this.subjectId, required this.subjectName});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LessonProvider>().loadLessons(widget.subjectId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LessonProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(widget.subjectName)),
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
        itemBuilder: (_, __) => const SkeletonBox(height: 64),
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

    return ListView.builder(
      itemCount: provider.lessons.length,
      itemBuilder: (context, index) {
        final lesson = provider.lessons[index];
        return LessonCard(
          lesson: lesson,
          onTap: () => context.push('/lesson-player', extra: {'lessonId': lesson.id}),
        );
      },
    );
  }
}
