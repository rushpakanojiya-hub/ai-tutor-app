import '../core/constants/api_constants.dart';
import '../models/ai_content_model.dart';
import '../models/lesson_model.dart';
import '../models/note_model.dart';
import '../models/subject_progress_model.dart';
import 'api_service.dart';

/// Talks to the backend's /api/lessons, /api/notes, /api/progress, and
/// /api/lessons/:id/ai-content endpoints.
class LessonService {
  final ApiService _api = ApiService();

  Future<List<LessonModel>> fetchLessonsBySubject(int subjectId) async {
    final response = await _api.get(ApiConstants.subjectLessons(subjectId));
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => LessonModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<LessonModel> fetchLessonById(int lessonId) async {
    final response = await _api.get(ApiConstants.lessonById(lessonId));
    return LessonModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<NoteModel>> fetchNotesByLesson(int lessonId) async {
    final response = await _api.get(ApiConstants.lessonNotes(lessonId));
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => NoteModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Fetches AI-generated explanation/summary/key points/examples/practice
  /// questions/quiz for a lesson. Throws ApiException with statusCode 404
  /// if this lesson has no AI content generated yet â€” callers should treat
  /// that as an empty state, not a hard error.
  Future<AiContentModel> fetchAiContent(int lessonId) async {
    final response = await _api.get(ApiConstants.lessonAiContent(lessonId));
    return AiContentModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// Persists lesson completion on the backend (lesson_progress table),
  /// optionally with a quiz score (0-100).
  Future<void> markLessonComplete(int lessonId, {int? score}) async {
    await _api.post(ApiConstants.markLessonComplete(lessonId), {
      if (score != null) 'score': score,
    });
  }

  /// Fetches how many of a subject's lessons the current user has
  /// completed, and which specific lesson IDs, for checkmarks + percentage.
  Future<SubjectProgressModel> fetchSubjectProgress(int subjectId) async {
    final response = await _api.get(ApiConstants.subjectProgress(subjectId));
    return SubjectProgressModel.fromJson(response['data'] as Map<String, dynamic>);
  }
}
