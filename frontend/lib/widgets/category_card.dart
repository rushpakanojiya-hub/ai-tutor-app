import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/category_model.dart';

/// Maps a category's icon name (from the backend) to a Flutter icon.
/// Backend stores plain strings like "school", "code" â€” Icons.* constants
/// are used here instead of raw emoji/unicode to avoid the PowerShell
/// encoding corruption issue seen on other projects.
IconData _iconFor(String icon) {
  switch (icon) {
    case 'school':
      return Icons.school_rounded;
    case 'code':
      return Icons.code_rounded;
    case 'science':
      return Icons.science_rounded;
    case 'calculate':
      return Icons.calculate_rounded;
    case 'translate':
      return Icons.translate_rounded;
    case 'emoji_events':
      return Icons.emoji_events_rounded;
    default:
      return Icons.menu_book_rounded;
  }
}

class CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onTap;

  const CategoryCard({super.key, required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(_iconFor(category.icon), color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                category.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
