import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/subject_model.dart';

class SubjectCard extends StatelessWidget {
  final SubjectModel subject;
  final VoidCallback onTap;

  const SubjectCard({super.key, required this.subject, required this.onTap});

  Color get _difficultyColor {
    switch (subject.difficulty) {
      case 'Beginner':
        return AppColors.green;
      case 'Advanced':
        return AppColors.error;
      default:
        return AppColors.orange;
    }
  }

  Color get _difficultyBg {
    switch (subject.difficulty) {
      case 'Beginner':
        return AppColors.greenLight;
      case 'Advanced':
        return const Color(0xFFFDE8E6);
      default:
        return AppColors.orangeLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: AppColors.purple.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: subject.thumbnail.isNotEmpty
                        ? Image.network(
                            subject.thumbnail,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => _placeholderThumbnail(),
                          )
                        : _placeholderThumbnail(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: _difficultyBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            subject.difficulty,
                            style: TextStyle(color: _difficultyColor, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: AppColors.purpleLight, shape: BoxShape.circle),
                    child: const Icon(Icons.chevron_right_rounded, color: AppColors.purple, size: 20),
                  ),
                ],
              ),
              if (subject.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  subject.description,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statChip(Icons.menu_book_outlined, '${subject.lessonCount} lessons'),
                  _statChip(Icons.quiz_outlined, subject.quizCount > 0 ? '${subject.quizCount} quizzes' : 'Quizzes coming soon'),
                  _statChip(Icons.description_outlined, '${subject.notesCount} notes'),
                  _statChip(Icons.schedule_rounded, '${subject.learningHours.toStringAsFixed(1)}h'),
                ],
              ),
              const SizedBox(height: 12),
              _progressBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.purpleLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.purple),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.purple, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _progressBar() {
    final pct = subject.progressPercentage.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Progress', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(color: AppColors.purple, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 6,
            backgroundColor: AppColors.purpleLight,
            valueColor: const AlwaysStoppedAnimation(AppColors.purple),
          ),
        ),
      ],
    );
  }

  Widget _placeholderThumbnail() {
    return Container(
      width: 56,
      height: 56,
      color: AppColors.purpleLight,
      child: const Icon(Icons.menu_book_rounded, color: AppColors.purple),
    );
  }
}
