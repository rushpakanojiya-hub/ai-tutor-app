import '../core/constants/api_constants.dart';
import '../models/lesson_model.dart';
import '../models/note_model.dart';
import 'api_service.dart';

/// Talks to the backend's /api/lessons and /api/notes endpoints.
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
}
