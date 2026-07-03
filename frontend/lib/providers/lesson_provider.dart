import 'package:flutter/material.dart';
import '../models/lesson_model.dart';
import '../models/note_model.dart';
import '../services/api_service.dart';
import '../services/lesson_service.dart';

/// Holds lesson list + notes state for LessonsScreen and LessonPlayerScreen.
class LessonProvider extends ChangeNotifier {
  final LessonService _service = LessonService();

  List<LessonModel> lessons = [];
  bool isLoading = false;
  String? errorMessage;

  List<NoteModel> notes = [];
  bool isLoadingNotes = false;
  String? notesErrorMessage;

  Future<void> loadLessons(int subjectId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      lessons = await _service.fetchLessonsBySubject(subjectId);
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

  /// Marks a lesson as watched locally (see LessonModel.isCompleted comment
  /// â€” there is no backend progress-tracking feature in Day 2).
  void markCompleted(int lessonId) {
    final index = lessons.indexWhere((l) => l.id == lessonId);
    if (index != -1) {
      lessons[index].isCompleted = true;
      notifyListeners();
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
