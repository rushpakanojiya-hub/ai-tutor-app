import 'package:flutter/foundation.dart';
import '../models/youtube_video.dart';
import '../services/api_service.dart';
import '../services/youtube_service.dart';

enum YoutubeLoadStatus { idle, loading, loaded, empty, error }

class YoutubeProvider extends ChangeNotifier {
  final YoutubeService _service = YoutubeService();

  YoutubeLoadStatus status = YoutubeLoadStatus.idle;
  List<YoutubeVideo> videos = [];
  String? errorMessage;
  int? _currentLessonId;

  Future<void> loadVideosForLesson(int lessonId) async {
    _currentLessonId = lessonId;
    status = YoutubeLoadStatus.loading;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _service.getLessonVideos(lessonId);
      videos = result;
      status = result.isEmpty ? YoutubeLoadStatus.empty : YoutubeLoadStatus.loaded;
    } on ApiException catch (e) {
      status = YoutubeLoadStatus.error;
      errorMessage = e.message;
    } catch (e) {
      status = YoutubeLoadStatus.error;
      errorMessage = 'Something went wrong. Please check your connection.';
    }
    notifyListeners();
  }

  Future<void> retry() async {
    if (_currentLessonId != null) {
      await loadVideosForLesson(_currentLessonId!);
    }
  }

  Future<void> recordProgress({
    required String videoId,
    required int watchedSeconds,
    required bool completed,
  }) async {
    if (_currentLessonId == null) return;
    try {
      await _service.saveProgress(
        lessonId: _currentLessonId!,
        videoId: videoId,
        watchedSeconds: watchedSeconds,
        completed: completed,
      );
    } catch (e) {
      debugPrint('youtube_provider: failed to save progress: $e');
    }
  }
}
