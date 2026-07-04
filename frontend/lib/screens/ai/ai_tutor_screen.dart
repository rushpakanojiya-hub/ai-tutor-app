import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// AI Tutor home: 4 entry points â€” Ask Question (subject-scoped chat),
/// Homework Help, Chat History, and Recommendations. Reached from the
/// Dashboard's "AI Tutor" card / bottom nav tab.
class AiTutorScreen extends StatelessWidget {
  const AiTutorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Tutor')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How can I help you learn today?',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _card(
              context,
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.purple,
              bg: AppColors.purpleLight,
              title: 'Ask Question',
              subtitle: 'Chat with the AI Tutor about any subject',
              onTap: () => context.push('/ai-chat'),
            ),
            const SizedBox(height: 14),
            _card(
              context,
              icon: Icons.edit_note_rounded,
              color: AppColors.orange,
              bg: AppColors.orangeLight,
              title: 'Homework Help',
              subtitle: 'Get step-by-step help with your homework',
              onTap: () => context.push('/ai-homework'),
            ),
            const SizedBox(height: 14),
            _card(
              context,
              icon: Icons.history_rounded,
              color: AppColors.blue,
              bg: AppColors.blueLight,
              title: 'Chat History',
              subtitle: 'Revisit your past conversations',
              onTap: () => context.push('/ai-history'),
            ),
            const SizedBox(height: 14),
            _card(
              context,
              icon: Icons.auto_awesome_rounded,
              color: AppColors.green,
              bg: AppColors.greenLight,
              title: 'Recommendations',
              subtitle: 'See what to learn next',
              onTap: () => context.push('/ai-recommendations'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required Color bg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
