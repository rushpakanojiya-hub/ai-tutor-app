import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/ai_provider.dart';
import '../../widgets/recommendation_card.dart';
import '../../widgets/skeleton_box.dart';

/// "What to learn next" â€” rule-based recommendations computed from the
/// student's completed lessons (see backend internal/recommendations).
class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({super.key});

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AiProvider>().loadRecommendations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Recommendations')),
      body: RefreshIndicator(
        onRefresh: () => provider.loadRecommendations(),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(provider),
        ),
      ),
    );
  }

  Widget _buildBody(AiProvider provider) {
    if (provider.isLoadingRecommendations) {
      return ListView.separated(
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => SkeletonBox(height: 76, borderRadius: BorderRadius.circular(18)),
      );
    }

    if (provider.recommendationsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(provider.recommendationsError!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => provider.loadRecommendations(), child: const Text('Retry')),
          ],
        ),
      );
    }

    if (provider.recommendations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text('No recommendations yet.', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            const Text('Complete a few lessons to get personalized suggestions!', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => context.push('/categories'), child: const Text('Browse Courses')),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: provider.recommendations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final rec = provider.recommendations[index];
        return RecommendationCard(
          recommendation: rec,
          onTap: () => context.push('/lesson-player', extra: {'lessonId': rec.recommendedLessonId}),
        );
      },
    );
  }
}
