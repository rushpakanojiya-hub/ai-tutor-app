import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/youtube_video.dart';
import '../providers/youtube_provider.dart';
import '../widgets/video_card.dart';

/// Drop this screen/widget in between "AI Explanation" and "PDF Notes"
/// in your existing lesson detail flow. It does not alter AI Explanation,
/// PDF Notes, or Mark Complete — those stay exactly as they are.
///
/// Videos open externally in the YouTube app/browser (same pattern as PDF
/// notes elsewhere in this app) rather than an embedded in-app player,
/// since in-app WebView playback is unreliable on many devices due to
/// Android's third-party cookie restrictions breaking YouTube's iframe
/// embed API. Trade-off: exact watched-seconds tracking isn't possible
/// once playback happens outside the app, so we record a lightweight
/// "started watching" event instead of continuous position updates.
class LessonVideosScreen extends StatefulWidget {
  final int lessonId;
  final String lessonTitle;

  const LessonVideosScreen({
    super.key,
    required this.lessonId,
    required this.lessonTitle,
  });

  @override
  State<LessonVideosScreen> createState() => _LessonVideosScreenState();
}

class _LessonVideosScreenState extends State<LessonVideosScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<YoutubeProvider>().loadVideosForLesson(widget.lessonId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<YoutubeProvider>(
      builder: (context, provider, _) {
        switch (provider.status) {
          case YoutubeLoadStatus.idle:
          case YoutubeLoadStatus.loading:
            return _buildSkeleton();
          case YoutubeLoadStatus.error:
            return _buildError(provider);
          case YoutubeLoadStatus.empty:
            return _buildEmpty();
          case YoutubeLoadStatus.loaded:
            return _buildVideoList(context, provider.videos);
        }
      },
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Shimmer(
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(YoutubeProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 36, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            provider.errorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => provider.retry(),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text('Retry', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No educational videos found.',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text('Continue learning with:', style: GoogleFonts.poppins(fontSize: 13)),
          Text('✓ AI Explanation', style: GoogleFonts.poppins(fontSize: 13)),
          Text('✓ PDF Notes', style: GoogleFonts.poppins(fontSize: 13)),
          Text('✓ Practice Questions', style: GoogleFonts.poppins(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildVideoList(BuildContext context, List<YoutubeVideo> videos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recommended Videos',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...videos.asMap().entries.map(
              (entry) => VideoCard(
                video: entry.value,
                index: entry.key,
                onWatch: () => _openExternally(context, entry.value),
              ),
            ),
      ],
    );
  }

  Future<void> _openExternally(BuildContext context, YoutubeVideo video) async {
    final provider = context.read<YoutubeProvider>();
    // Record a lightweight "started watching" event — exact seconds aren't
    // trackable once playback moves outside the app.
    provider.recordProgress(videoId: video.videoId, watchedSeconds: 0, completed: false);

    final uri = Uri.parse('https://www.youtube.com/watch?v=${video.videoId}');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the video. Please try again.')),
      );
    }
  }
}

/// Minimal shimmer effect with no external dependency.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + (0.5 * (1 - (_controller.value - 0.5).abs() * 2)),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
