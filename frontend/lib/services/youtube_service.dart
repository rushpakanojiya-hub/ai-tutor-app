import '../core/constants/api_constants.dart';
import '../models/youtube_video.dart';
import 'api_service.dart';

/// Talks to the Go backend's YouTube endpoints, using the same shared
/// ApiService (Dio + auth header injection) as the rest of the app.
class YoutubeService {
  final ApiService _api = ApiService();

  /// GET /api/lessons/:id/videos
  Future<List<YoutubeVideo>> getLessonVideos(int lessonId) async {
    final result = await _api.get(ApiConstants.lessonVideos(lessonId));
    final list = (result['data'] ?? result['videos'] ?? []) as List;
    return list
        .map((json) => YoutubeVideo.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/videos/search?q=
  Future<List<YoutubeVideo>> searchVideos(String query) async {
    final result = await _api.get(
      '${ApiConstants.videoSearch}?q=${Uri.encodeQueryComponent(query)}',
    );
    final list = (result['data'] ?? result['videos'] ?? []) as List;
    return list
        .map((json) => YoutubeVideo.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/lessons/:id/videos/progress
  Future<void> saveProgress({
    required int lessonId,
    required String videoId,
    required int watchedSeconds,
    required bool completed,
  }) async {
    await _api.post(
      ApiConstants.lessonVideoProgress(lessonId),
      {
        'video_id': videoId,
        'watched_seconds': watchedSeconds,
        'completed': completed,
      },
    );
  }
}
