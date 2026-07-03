import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/subject_model.dart';

class SubjectCard extends StatelessWidget {
  final SubjectModel subject;
  final VoidCallback onTap;

  const SubjectCard({super.key, required this.subject, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail (or a placeholder icon when the backend has none).
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: subject.thumbnail.isNotEmpty
                  ? Image.network(
                      subject.thumbnail,
                      width: 64,
                      height: 64,
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
                  if (subject.description.isNotEmpty)
                    Text(
                      subject.description,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        '${subject.lessonCount} lessons',
                        style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _placeholderThumbnail() {
    return Container(
      width: 64,
      height: 64,
      color: AppColors.primary.withOpacity(0.1),
      child: const Icon(Icons.menu_book_rounded, color: AppColors.primary),
    );
  }
}
