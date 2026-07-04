import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/category_model.dart';

/// Maps a category's icon name (from the backend) to a Material icon.
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

/// Cycles categories through the pastel palette so the grid doesn't look
/// monochrome â€” purely cosmetic, unrelated to backend data.
const _palette = [
  (bg: AppColors.purpleLight, fg: AppColors.purple),
  (bg: AppColors.orangeLight, fg: AppColors.orange),
  (bg: AppColors.blueLight, fg: AppColors.blue),
  (bg: AppColors.greenLight, fg: AppColors.green),
];

class CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onTap;

  const CategoryCard({super.key, required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = _palette[category.id % _palette.length];

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: colors.fg.withOpacity(0.15),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colors.bg, shape: BoxShape.circle),
                child: Icon(_iconFor(category.icon), color: colors.fg, size: 28),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  category.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
