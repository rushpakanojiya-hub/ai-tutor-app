$files = @{}
$files['pubspec.yaml'] = @'
name: ai_tutor_app
description: AI Tutor Mobile Application MVP - Day 1 (Auth + Dashboard shell)
publish_to: 'none'
version: 0.1.0

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6

  # State management
  provider: ^6.1.2

  # Networking
  dio: ^5.4.3+1

  # Local storage (JWT token, user info)
  shared_preferences: ^2.2.3

  # Navigation
  go_router: ^14.2.0

  # Day 2: video playback
  video_player: ^2.9.1
  chewie: ^1.8.5

  # Day 2: PDF notes (opened externally to avoid native PDF-render plugin
  # Gradle conflicts with newer Android Gradle Plugin versions)
  url_launcher: ^6.3.0

  # UI redesign (visual only — no logic changes)
  google_fonts: ^6.2.1
  flutter_animate: ^4.5.0
  flutter_svg: ^2.0.10+1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true

'@
$files['lib\screens\dashboard\dashboard_screen.dart'] = @'
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../categories/categories_screen.dart';
import '../profile/profile_screen.dart';

/// Student dashboard shell. UI redesign only — navigation targets,
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
    _PlaceholderTab(title: 'AI Tutor'),
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

class _DashboardHome extends StatelessWidget {
  const _DashboardHome();

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
          onTap: () => _showComingSoon(context, 'AI Tutor'),
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
        // Illustrative example only — Day 2 has no "recent progress" API yet,
        // so this section shows sample cards rather than live data. Once a
        // backend endpoint exists, replace this static list with a provider.
        const _ContinueLearningCard(
          title: 'Mathematics Basics',
          meta: 'Algebra - Lesson 3 of 10',
          progress: 0.3,
          icon: Icons.calculate_rounded,
          color: AppColors.orange,
        ).animate().fadeIn(duration: 300.ms, delay: 340.ms),
        const SizedBox(height: 12),
        _ContinueLearningCard(
          title: 'Science Fundamentals',
          meta: 'Physics - Lesson 2 of 8',
          progress: 0.25,
          icon: Icons.science_rounded,
          color: AppColors.purple,
        ).animate().fadeIn(duration: 300.ms, delay: 400.ms),
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
/// button. Illustrative/static — see comment above where it's used.
class _ContinueLearningCard extends StatelessWidget {
  final String title;
  final String meta;
  final double progress;
  final IconData icon;
  final Color color;

  const _ContinueLearningCard({
    required this.title,
    required this.meta,
    required this.progress,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
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

'@
$files['lib\widgets\category_card.dart'] = @'
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
/// monochrome — purely cosmetic, unrelated to backend data.
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

'@
$files['lib\widgets\subject_card.dart'] = @'
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/subject_model.dart';

class SubjectCard extends StatelessWidget {
  final SubjectModel subject;
  final VoidCallback onTap;

  const SubjectCard({super.key, required this.subject, required this.onTap});

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
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: subject.thumbnail.isNotEmpty
                    ? Image.network(
                        subject.thumbnail,
                        width: 60,
                        height: 60,
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
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.purpleLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.menu_book_outlined, size: 13, color: AppColors.purple),
                          const SizedBox(width: 4),
                          Text(
                            '${subject.lessonCount} lessons',
                            style: const TextStyle(color: AppColors.purple, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
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
        ),
      ),
    );
  }

  Widget _placeholderThumbnail() {
    return Container(
      width: 60,
      height: 60,
      color: AppColors.purpleLight,
      child: const Icon(Icons.menu_book_rounded, color: AppColors.purple),
    );
  }
}

'@
$files['lib\widgets\lesson_card.dart'] = @'
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/lesson_model.dart';

class LessonCard extends StatelessWidget {
  final LessonModel lesson;
  final VoidCallback onTap;

  const LessonCard({super.key, required this.lesson, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = lesson.isCompleted;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.purple.withOpacity(0.1),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: done ? AppColors.greenLight : const Color(0xFFF1F1F6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  done ? Icons.check_rounded : Icons.play_arrow_rounded,
                  color: done ? AppColors.green : AppColors.textSecondary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lesson ${lesson.orderNumber}: ${lesson.title}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('${lesson.duration} min', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(width: 10),
                        const Icon(Icons.videocam_outlined, size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        const Text('Video lesson', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: AppColors.purple, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

'@
$files['lib\screens\lessons\lesson_player_screen.dart'] = @'
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/lesson_model.dart';
import '../../providers/lesson_provider.dart';
import '../../services/lesson_service.dart';
import '../../widgets/notes_widget.dart';

/// Feature 4 + 5: full lesson player — video, description, Previous/Next
/// navigation, and the PDF notes section for the same lesson.
/// UI redesign only — all loading/video/navigation logic below is unchanged.
class LessonPlayerScreen extends StatefulWidget {
  final int lessonId;

  const LessonPlayerScreen({super.key, required this.lessonId});

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  final LessonService _lessonService = LessonService();

  LessonModel? _lesson;
  bool _isLoading = true;
  String? _errorMessage;

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _loadLesson(widget.lessonId);
  }

  Future<void> _loadLesson(int lessonId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _disposeVideo();

    try {
      final lesson = await _lessonService.fetchLessonById(lessonId);
      setState(() => _lesson = lesson);

      if (lesson.videoUrl.isNotEmpty) {
        await _initVideo(lesson.videoUrl);
      }

      if (mounted) {
        await context.read<LessonProvider>().loadNotes(lessonId);
        context.read<LessonProvider>().markCompleted(lessonId);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Could not load this lesson. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initVideo(String url) async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
        errorBuilder: (context, errorMessage) => Center(
          child: Text(errorMessage, style: const TextStyle(color: Colors.white)),
        ),
      );
      _videoController = controller;
      if (mounted) setState(() {});
    } catch (e) {
      // Video failed to load (bad URL, network issue) — the rest of the
      // screen (description, notes, navigation) still works without it.
      _videoController = null;
      _chewieController = null;
    }
  }

  void _disposeVideo() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  void _goToLesson(LessonModel? target) {
    if (target == null) return;
    _loadLesson(target.id);
  }

  @override
  Widget build(BuildContext context) {
    final lessonProvider = context.watch<LessonProvider>();
    final previous = _lesson != null ? lessonProvider.previousOf(_lesson!.id) : null;
    final next = _lesson != null ? lessonProvider.nextOf(_lesson!.id) : null;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(_lesson?.title ?? 'Lesson')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: () => _loadLesson(widget.lessonId), child: const Text('Retry')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: _buildVideoArea(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: AppTheme.softShadow,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_lesson!.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.purpleLight,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.access_time_rounded, size: 14, color: AppColors.purple),
                                        const SizedBox(width: 6),
                                        Text('${_lesson!.duration} minutes', style: const TextStyle(color: AppColors.purple, fontSize: 12, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  if (_lesson!.description.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(height: 6),
                                    Text(_lesson!.description, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: previous != null ? () => _goToLesson(previous) : null,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(50),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    icon: const Icon(Icons.skip_previous_rounded),
                                    label: const Text('Previous'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: next != null ? () => _goToLesson(next) : null,
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(50),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    icon: const Icon(Icons.skip_next_rounded),
                                    label: const Text('Next'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => context.read<LessonProvider>().markCompleted(_lesson!.id),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  foregroundColor: AppColors.green,
                                  side: const BorderSide(color: AppColors.green),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                icon: const Icon(Icons.check_circle_outline_rounded),
                                label: const Text('Mark Complete'),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: AppTheme.softShadow,
                              ),
                              child: NotesWidget(
                                notes: lessonProvider.notes,
                                isLoading: lessonProvider.isLoadingNotes,
                                errorMessage: lessonProvider.notesErrorMessage,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildVideoArea() {
    if (_lesson == null || _lesson!.videoUrl.isEmpty) {
      return Container(
        height: 200,
        color: Colors.black12,
        child: const Center(
          child: Text('No video available for this lesson.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    if (_chewieController == null) {
      return Container(
        height: 200,
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return AspectRatio(
      aspectRatio: _chewieController!.aspectRatio ?? 16 / 9,
      child: Chewie(controller: _chewieController!),
    );
  }
}

'@
$files['lib\screens\profile\profile_screen.dart'] = @'
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

/// Profile tab: shows the logged-in user's info and a logout button.
/// UI redesign only — AuthProvider.logout() and the navigation after it
/// are exactly what they were before.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(color: AppColors.purpleLight, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      (user?.name.isNotEmpty == true ? user!.name[0] : '?').toUpperCase(),
                      style: const TextStyle(fontSize: 34, color: AppColors.purple, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(user?.name ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    (user?.role ?? '-').toUpperCase(),
                    style: const TextStyle(color: AppColors.purple, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),

          const SizedBox(height: 20),

          _ProfileMenuTile(
            icon: Icons.edit_outlined,
            label: 'Edit Profile',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edit profile is coming in a later build')),
              );
            },
          ).animate().fadeIn(duration: 250.ms, delay: 100.ms),
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.logout_rounded,
            label: 'Logout',
            color: AppColors.error,
            onTap: () async {
              await context.read<AuthProvider>().logout();
              if (context.mounted) context.go('/login');
            },
          ).animate().fadeIn(duration: 250.ms, delay: 160.ms),
        ],
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ProfileMenuTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.textPrimary;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 22),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w600, fontSize: 15))),
              Icon(Icons.chevron_right_rounded, color: tint.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

'@

foreach ($path in $files.Keys) {
    $fullPath = Join-Path $PWD $path
    $dir = Split-Path $fullPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($fullPath, $files[$path], [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated: $path"
}
Write-Host ""
Write-Host "MdiIcons removed, fix applied successfully."
