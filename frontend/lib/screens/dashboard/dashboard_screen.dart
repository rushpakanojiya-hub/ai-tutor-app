import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subject_progress_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/lesson_service.dart';
import '../../services/storage_service.dart';
import '../categories/categories_screen.dart';
import '../ai/ai_home_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/skeleton_box.dart';

/// Student dashboard shell. UI redesign only â€” navigation targets,
/// providers, and the tab list are unchanged from before.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  final _pages = const [
    _DashboardHome(),
    CategoriesScreen(),
    AiHomeScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Courses'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'AI Tutor'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _DashboardHome extends StatefulWidget {
  const _DashboardHome();

  @override
  State<_DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<_DashboardHome> {
  final LessonService _lessonService = LessonService();
  final StorageService _storage = StorageService();

  int? _lastSubjectId;
  String? _lastSubjectName;
  SubjectProgressModel? _lastSubjectProgress;
  bool _loadingProgress = true;

  @override
  void initState() {
    super.initState();
    _loadContinueLearning();
  }

  /// Reads the most recently opened subject (saved by LessonsScreen) and
  /// fetches its real completion percentage from the backend. If the user
  /// hasn't opened any subject yet, this stays null and the dashboard falls
  /// back to the illustrative example cards below.
  Future<void> _loadContinueLearning() async {
    final id = await _storage.getInt(AppConstants.keyLastSubjectId);
    final name = await _storage.getString(AppConstants.keyLastSubjectName);

    if (id != null && name != null) {
      try {
        final progress = await _lessonService.fetchSubjectProgress(id);
        if (mounted) {
          setState(() {
            _lastSubjectId = id;
            _lastSubjectName = name;
            _lastSubjectProgress = progress;
          });
        }
      } catch (_) {
        // No connectivity / subject deleted â€” fall back to example cards.
      }
    }

    if (mounted) setState(() => _loadingProgress = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'Hello, ${user?.name ?? 'Student'} \u{1F44B}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0),
        const SizedBox(height: 4),
        const Text(
          'Ready to continue learning today?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ).animate().fadeIn(duration: 350.ms, delay: 80.ms),
        const SizedBox(height: 24),

        _DashboardActionCard(
          icon: Icons.menu_book_rounded,
          iconBg: AppColors.purpleLight,
          iconColor: AppColors.purple,
          title: 'My Courses',
          subtitle: 'Continue learning',
          onTap: () => context.push('/categories'),
        ).animate().fadeIn(duration: 300.ms, delay: 100.ms).slideY(begin: 0.15, end: 0),
        const SizedBox(height: 14),
        _DashboardActionCard(
          icon: Icons.smart_toy_rounded,
          iconBg: AppColors.orangeLight,
          iconColor: AppColors.orange,
          title: 'AI Tutor',
          subtitle: 'Ask anything',
          onTap: () => context.push('/ai-tutor'),
        ).animate().fadeIn(duration: 300.ms, delay: 160.ms).slideY(begin: 0.15, end: 0),
        const SizedBox(height: 14),
        _DashboardActionCard(
          icon: Icons.help_outline_rounded,
          iconBg: AppColors.blueLight,
          iconColor: AppColors.blue,
          title: 'Quiz',
          subtitle: 'Test your knowledge',
          onTap: () => _showComingSoon(context, 'Quiz'),
        ).animate().fadeIn(duration: 300.ms, delay: 220.ms).slideY(begin: 0.15, end: 0),
        const SizedBox(height: 14),
        _DashboardActionCard(
          icon: Icons.trending_up_rounded,
          iconBg: AppColors.greenLight,
          iconColor: AppColors.green,
          title: 'Progress',
          subtitle: 'Track your growth',
          onTap: () => _showComingSoon(context, 'Progress'),
        ).animate().fadeIn(duration: 300.ms, delay: 280.ms).slideY(begin: 0.15, end: 0),

        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Continue Learning', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            TextButton(
              onPressed: () => context.push('/categories'),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildContinueLearning(),
      ],
    );
  }

  Widget _buildContinueLearning() {
    if (_loadingProgress) {
      return SkeletonBox(height: 84, borderRadius: BorderRadius.circular(20));
    }

    // Real data: the subject the user most recently opened, with its
    // actual completion percentage from the backend.
    if (_lastSubjectId != null && _lastSubjectProgress != null) {
      final p = _lastSubjectProgress!;
      return _ContinueLearningCard(
        title: _lastSubjectName!,
        meta: '${p.completedLessons} of ${p.totalLessons} lessons complete',
        progress: p.percentage,
        icon: Icons.menu_book_rounded,
        color: AppColors.purple,
        onTap: () => context.push('/lessons', extra: {'subjectId': _lastSubjectId, 'subjectName': _lastSubjectName}),
      ).animate().fadeIn(duration: 300.ms, delay: 340.ms);
    }

    // No subject opened yet â€” illustrative example so the section isn't
    // empty on a brand-new account. Tapping it leads into real categories.
    return Column(
      children: [
        _ContinueLearningCard(
          title: 'Mathematics Basics',
          meta: 'Start your first lesson',
          progress: 0,
          icon: Icons.calculate_rounded,
          color: AppColors.orange,
          onTap: () => context.push('/categories'),
        ).animate().fadeIn(duration: 300.ms, delay: 340.ms),
      ],
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming in a later build'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Full-width vertical action card used for My Courses / AI Tutor / Quiz /
/// Progress on the dashboard home tab.
class _DashboardActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DashboardActionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: iconBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: iconColor.withOpacity(0.15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: iconColor)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: iconColor.withOpacity(0.85))),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Continue Learning" card: subject icon, progress bar, and a Continue
/// button.
class _ContinueLearningCard extends StatelessWidget {
  final String title;
  final String meta;
  final double progress;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ContinueLearningCard({
    required this.title,
    required this.meta,
    required this.progress,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(meta, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: color.withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  final String title;
  const _PlaceholderTab({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('$title - coming soon', style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
    );
  }
}
