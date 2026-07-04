import 'package:flutter/material.dart';
import '../models/ai_content_model.dart';
import '../models/lesson_model.dart';
import '../models/note_model.dart';
import '../models/subject_progress_model.dart';
import '../services/api_service.dart';
import '../services/lesson_service.dart';

/// Holds lesson list + notes + AI content + progress state for
/// LessonsScreen, LessonPlayerScreen, and QuizScreen. Completion is
/// persisted on the backend (lesson_progress table), optionally with a quiz
/// score, instead of an in-memory-only flag.
class LessonProvider extends ChangeNotifier {
  final LessonService _service = LessonService();

  List<LessonModel> lessons = [];
  bool isLoading = false;
  String? errorMessage;

  List<NoteModel> notes = [];
  bool isLoadingNotes = false;
  String? notesErrorMessage;

  AiContentModel? aiContent;
  bool isLoadingAiContent = false;
  String? aiContentErrorMessage;
  bool aiContentUnavailable = false; // true = "not generated yet", not an error

  SubjectProgressModel? subjectProgress;

  /// Loads a subject's lessons, then fetches the current user's completion
  /// status for that subject and applies it to each LessonModel â€” so
  /// checkmarks reflect real, persisted progress.
  Future<void> loadLessons(int subjectId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      lessons = await _service.fetchLessonsBySubject(subjectId);

      try {
        subjectProgress = await _service.fetchSubjectProgress(subjectId);
        final completedIds = subjectProgress!.completedLessonIds.toSet();
        for (final lesson in lessons) {
          lesson.isCompleted = completedIds.contains(lesson.id);
        }
      } catch (_) {
        subjectProgress = null;
      }
    } on ApiException catch (e) {
      errorMessage = e.message;
    } catch (e) {
      errorMessage = 'Something went wrong. Please try again.';
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> loadNotes(int lessonId) async {
    isLoadingNotes = true;
    notesErrorMessage = null;
    notifyListeners();

    try {
      notes = await _service.fetchNotesByLesson(lessonId);
    } on ApiException catch (e) {
      notesErrorMessage = e.message;
    } catch (e) {
      notesErrorMessage = 'Could not load notes.';
    }

    isLoadingNotes = false;
    notifyListeners();
  }

  /// Loads AI-generated explanation/summary/key points/examples/practice
  /// questions/quiz for a lesson. A 404 means "not generated for this
  /// lesson yet" â€” treated as an empty state (aiContentUnavailable), not
  /// an error banner.
  Future<void> loadAiContent(int lessonId) async {
    isLoadingAiContent = true;
    aiContentErrorMessage = null;
    aiContentUnavailable = false;
    aiContent = null;
    notifyListeners();

    try {
      aiContent = await _service.fetchAiContent(lessonId);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        aiContentUnavailable = true;
      } else {
        aiContentErrorMessage = e.message;
      }
    } catch (e) {
      aiContentErrorMessage = 'Could not load AI content.';
    }

    isLoadingAiContent = false;
    notifyListeners();
  }

  /// Marks a lesson complete both locally (instant checkmark) and on the
  /// backend (persisted), optionally with a quiz score (0-100). If the API
  /// call fails, the local checkmark stays â€” the next screen visit will
  /// resync from the server.
  Future<void> markCompleted(int lessonId, {int? score}) async {
    final index = lessons.indexWhere((l) => l.id == lessonId);
    if (index != -1) {
      lessons[index].isCompleted = true;
      notifyListeners();
    }

    try {
      await _service.markLessonComplete(lessonId, score: score);
    } catch (_) {
      // Best-effort â€” see doc comment above.
    }
  }

  /// Returns the lesson before/after the given one in the current list,
  /// or null at the boundaries â€” used by the Previous/Next buttons.
  LessonModel? previousOf(int lessonId) {
    final index = lessons.indexWhere((l) => l.id == lessonId);
    if (index <= 0) return null;
    return lessons[index - 1];
  }

  LessonModel? nextOf(int lessonId) {
    final index = lessons.indexWhere((l) => l.id == lessonId);
    if (index == -1 || index >= lessons.length - 1) return null;
    return lessons[index + 1];
  }
}
