import '../core/constants/api_constants.dart';
import '../models/quiz_attempt_model.dart';
import 'api_service.dart';

/// Talks to the backend's /api/quiz/* endpoints: submitting attempts
/// (graded server-side), quiz history, analytics, and the AI Quiz Generator.
class QuizService {
  final ApiService _api = ApiService();

  /// Submits a lesson-based quiz attempt (always single-correct MCQ).
  /// answers is index-aligned to the lesson's quiz questions; use -1 for
  /// a skipped question.
  Future<QuizAttemptResult> submitLessonAttempt({
    required int lessonId,
    required List<int> answers,
    required int timeTakenSeconds,
  }) async {
    final response = await _api.post(ApiConstants.submitLessonQuizAttempt(lessonId), {
      'answers': answers,
      'time_taken_seconds': timeTakenSeconds,
    });
    return QuizAttemptResult.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// Submits an AI-generated freeform quiz (not tied to a lesson), mixing
  /// whichever question types were used.
  Future<QuizAttemptResult> submitFreeformAttempt({
    int? subjectId,
    required String topic,
    required List<QuizAttemptQuestion> questions,
    required int timeTakenSeconds,
  }) async {
    final response = await _api.post(ApiConstants.submitFreeformQuizAttempt, {
      if (subjectId != null) 'subject_id': subjectId,
      'topic': topic,
      'time_taken_seconds': timeTakenSeconds,
      'questions': questions.map((q) => q.toAnsweredJson()).toList(),
    });
    return QuizAttemptResult.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// Quiz history, optionally filtered to one lesson.
  Future<List<QuizAttemptSummary>> fetchAttempts({int? lessonId}) async {
    final path = lessonId != null
        ? '${ApiConstants.quizAttempts}?lesson_id=$lessonId'
        : ApiConstants.quizAttempts;
    final response = await _api.get(path);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => QuizAttemptSummary.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Full per-question breakdown for one attempt (results/review screen).
  Future<QuizAttemptResult> fetchAttempt(int id) async {
    final response = await _api.get(ApiConstants.quizAttempt(id));
    return QuizAttemptResult.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// Accuracy analytics computed from the student's real attempt history.
  Future<QuizAnalyticsModel> fetchAnalytics() async {
    final response = await _api.get(ApiConstants.quizAnalytics);
    return QuizAnalyticsModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// AI Quiz Generator: asks the backend (Groq) for a fresh quiz on any
  /// topic, mixing the requested question types (defaults to Single
  /// Correct MCQ only if none are given).
  Future<List<QuizAttemptQuestion>> generateQuiz({
    int? subjectId,
    required String topic,
    int numQuestions = 5,
    String difficulty = 'medium',
    List<String>? questionTypes,
  }) async {
    final response = await _api.post(ApiConstants.quizGenerate, {
      if (subjectId != null) 'subject_id': subjectId,
      'topic': topic,
      'num_questions': numQuestions,
      'difficulty': difficulty,
      if (questionTypes != null && questionTypes.isNotEmpty) 'question_types': questionTypes,
    });
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => QuizAttemptQuestion.fromJson(json as Map<String, dynamic>)).toList();
  }
}
