import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// In-app video player for Class Resources - reuses the same
/// video_player + chewie stack as lesson playback elsewhere in the app.
class ResourceVideoViewerScreen extends StatefulWidget {
  final String url;
  final String fileName;

  const ResourceVideoViewerScreen({super.key, required this.url, required this.fileName});

  @override
  State<ResourceVideoViewerScreen> createState() => _ResourceVideoViewerScreenState();
}

class _ResourceVideoViewerScreenState extends State<ResourceVideoViewerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      if (!mounted) {
        // BUG FIX (controller leak): dispose() already ran if we're
        // here unmounted, and won't run again - dispose this orphaned
        // controller directly instead of leaking it.
        await controller.dispose();
        return;
      }
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
        errorBuilder: (context, errorMessage) => Center(
          child: Text(errorMessage, style: const TextStyle(color: Colors.white)),
        ),
      );
      _videoController = controller;
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: _hasError
            ? const Text('Could not load this video.', style: TextStyle(color: Colors.white70))
            : (_chewieController != null
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Colors.white54)),
      ),
    );
  }
}
