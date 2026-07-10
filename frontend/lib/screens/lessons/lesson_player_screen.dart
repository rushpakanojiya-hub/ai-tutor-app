import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/lesson_model.dart';
import '../../providers/lesson_provider.dart';
import '../../services/lesson_service.dart';
import '../../widgets/notes_widget.dart';
import '../../widgets/skeleton_box.dart';
import '../lesson_videos_screen.dart';

/// Full lesson player: optional video, AI-generated explanation/key
/// points/examples/practice questions/summary, a Quiz button, recommended
/// YouTube videos, PDF notes, Previous/Next navigation, and Mark Complete.
///
/// If a lesson has no video, this screen shows the lesson's educational
/// thumbnail with "Educational content available — read notes below"
/// instead of an error, per the "no placeholder video" content strategy.
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
      // QA fix ("Missing mounted checks after async operations"): this
      // setState ran unconditionally right after an await - if the user
      // had already navigated away while the fetch was in flight, this
      // threw "setState() called after dispose()".
      if (!mounted) return;
      setState(() => _lesson = lesson);

      if (lesson.videoUrl.isNotEmpty) {
        await _initVideo(ApiConstants.resolveMediaUrl(lesson.videoUrl));
      }

      // QA fix ("Missing mounted checks after async operations"): two
      // separate awaits sit inside this single mounted-guard - if the
      // widget got unmounted during loadNotes() (between the two
      // calls), loadAiContent() below would still run against a
      // disposed context. Re-checking mounted between them closes that
      // gap instead of only checking once at the top.
      if (mounted) {
        await context.read<LessonProvider>().loadNotes(lessonId);
        if (mounted) {
          await context.read<LessonProvider>().loadAiContent(lessonId);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Could not load this lesson. Please try again.');
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
                          child: _buildMediaArea(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLessonHeaderCard(),
                            const SizedBox(height: 16),
                            _buildNavigationRow(previous, next),
                            const SizedBox(height: 12),
                            _buildMarkCompleteButton(),
                            const SizedBox(height: 24),
                            _buildAiContentSection(lessonProvider),
                            const SizedBox(height: 24),
                            _buildVideosSection(),
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

  /// Recommended Videos — sits between AI Explanation and PDF Notes.
  /// Does not touch AI content, notes, progress, or the video player above.
  Widget _buildVideosSection() {
    if (_lesson == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: LessonVideosScreen(
        lessonId: _lesson!.id,
        lessonTitle: _lesson!.title,
      ),
    );
  }

  Widget _buildLessonHeaderCard() {
    return Container(
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
            decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
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
    );
  }

  Widget _buildNavigationRow(LessonModel? previous, LessonModel? next) {
    return Row(
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
    );
  }

  Widget _buildMarkCompleteButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          await context.read<LessonProvider>().markCompleted(_lesson!.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lesson marked as complete')),
            );
          }
        },
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          foregroundColor: AppColors.green,
          side: const BorderSide(color: AppColors.green),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.check_circle_outline_rounded),
        label: const Text('Mark Complete'),
      ),
    );
  }

  Widget _buildAiContentSection(LessonProvider provider) {
    if (provider.isLoadingAiContent) {
      return Column(
        children: [
          SkeletonBox(height: 24, width: 160, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 12),
          SkeletonBox(height: 100, borderRadius: BorderRadius.circular(16)),
        ],
      );
    }

    if (provider.aiContentUnavailable) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.softShadow,
        ),
        child: const Text(
          'AI-generated notes for this lesson are not available yet. Check the PDF notes below.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    if (provider.aiContentErrorMessage != null) {
      return Text(provider.aiContentErrorMessage!, style: const TextStyle(color: AppColors.error));
    }

    final content = provider.aiContent;
    if (content == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _aiCard('Explanation', Icons.lightbulb_outline_rounded, Text(content.explanation, style: const TextStyle(height: 1.5))),
        const SizedBox(height: 14),
        if (content.keyPoints.isNotEmpty)
          _aiCard(
            'Key Points',
            Icons.checklist_rounded,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.keyPoints.map((p) => _bullet(p)).toList(),
            ),
          ),
        const SizedBox(height: 14),
        if (content.examples.isNotEmpty)
          _aiCard(
            'Examples',
            Icons.school_outlined,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.examples.map((p) => _bullet(p)).toList(),
            ),
          ),
        const SizedBox(height: 14),
        if (content.practiceQuestions.isNotEmpty)
          _aiCard(
            'Practice Questions',
            Icons.edit_note_rounded,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.practiceQuestions.map((p) => _bullet(p)).toList(),
            ),
          ),
        const SizedBox(height: 14),
        _aiCard('Summary', Icons.summarize_outlined, Text(content.summary, style: const TextStyle(height: 1.5))),
        if (content.quiz.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/quiz', extra: {'lessonId': _lesson!.id, 'questions': content.quiz}),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.quiz_rounded),
              label: const Text('Take Quiz'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _aiCard(String title, IconData icon, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.purple),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildMediaArea() {
    if (_lesson == null || _lesson!.videoUrl.isEmpty) {
      // No placeholder/cartoon video — show the lesson's educational
      // thumbnail (if any) with a message pointing to the notes below.
      final thumb = _lesson?.thumbnailUrl ?? '';
      return Container(
        height: 220,
        color: Colors.black12,
        child: thumb.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    ApiConstants.resolveMediaUrl(thumb),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                  Container(
                    color: Colors.black.withOpacity(0.35),
                    alignment: Alignment.center,
                    child: const Text(
                      'Educational content available\nRead notes below',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              )
            : const Center(
                child: Text(
                  'Educational content available\nRead notes below',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
      );
    }

    if (_chewieController == null) {
      return Container(
        height: 220,
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
