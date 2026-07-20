# apply_frontend_critical_fixes.ps1
# Run from your FRONTEND project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\frontend)
# Writes: quiz answer-tampering fix (matches backend's quiz_session_id flow)
# + live class room navigation double-pop fix (Critical #3 and #4 from the audit).
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying frontend critical fixes in $root" -ForegroundColor Cyan

# --- lib/models/quiz_attempt_model.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/models") | Out-Null
$content_lib_models_quiz_attempt_model_dart = @'
/// Response of POST /api/quiz/generate: the questions (answer-key
/// stripped by the backend - see quiz_service.dart) plus a session id
/// that must be sent back unchanged when submitting, so the server can
/// grade against the real answer key it stored at generation time.
class GeneratedQuiz {
  final String quizSessionId;
  final List<QuizAttemptQuestion> questions;

  GeneratedQuiz({required this.quizSessionId, required this.questions});

  factory GeneratedQuiz.fromJson(Map<String, dynamic> json) {
    final questionsJson = json['questions'] as List<dynamic>? ?? [];
    return GeneratedQuiz(
      quizSessionId: json['quiz_session_id'] as String? ?? '',
      questions: questionsJson.map((e) => QuizAttemptQuestion.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// Question type constants for the AI Quiz Generator (freeform quizzes).
/// Lesson-based quizzes are always singleMcq.
class QuestionTypes {
  QuestionTypes._();
  static const singleMcq = 'single_mcq';
  static const multipleMcq = 'multiple_mcq';
  static const trueFalse = 'true_false';
  static const fillBlank = 'fill_blank';
  static const shortAnswer = 'short_answer';

  static const all = [singleMcq, multipleMcq, trueFalse, fillBlank, shortAnswer];

  static String label(String type) {
    switch (type) {
      case multipleMcq:
        return 'Multiple Correct MCQ';
      case trueFalse:
        return 'True / False';
      case fillBlank:
        return 'Fill in the Blank';
      case shortAnswer:
        return 'Short Answer';
      default:
        return 'Single Correct MCQ';
    }
  }
}

/// A single quiz question paired with the student's answer - covers every
/// supported question type. Which fields are populated depends on
/// [questionType].
class QuizAttemptQuestion {
  final String questionType;
  final String question;
  final List<String> options;
  final int? correctOption;
  final List<int>? correctOptions;
  final String? correctText;
  final String? hint;
  final String? explanation;
  final int difficultyScore;

  final int? selectedOption;
  final List<int>? selectedOptions;
  final String? submittedText;
  final bool? isCorrect;

  QuizAttemptQuestion({
    this.questionType = QuestionTypes.singleMcq,
    required this.question,
    this.options = const [],
    this.correctOption,
    this.correctOptions,
    this.correctText,
    this.hint,
    this.explanation,
    this.difficultyScore = 5,
    this.selectedOption,
    this.selectedOptions,
    this.submittedText,
    this.isCorrect,
  });

  factory QuizAttemptQuestion.fromJson(Map<String, dynamic> json) {
    return QuizAttemptQuestion(
      questionType: json['question_type'] as String? ?? QuestionTypes.singleMcq,
      question: json['question_text'] ?? json['question'] ?? '',
      options: (json['options'] as List<dynamic>? ?? []).map((e) => e as String? ?? '').toList(),
      correctOption: json['correct_option'] as int?,
      correctOptions: (json['correct_options'] as List<dynamic>?)?.map((e) => e as int? ?? 0).toList(),
      correctText: json['correct_text'] as String?,
      hint: json['hint'] as String?,
      explanation: json['explanation'] as String?,
      difficultyScore: json['difficulty_score'] as int? ?? 5,
      selectedOption: json['selected_option'] as int?,
      selectedOptions: (json['selected_options'] as List<dynamic>?)?.map((e) => e as int? ?? 0).toList(),
      submittedText: json['submitted_text'] as String?,
      isCorrect: json['is_correct'] as bool?,
    );
  }

  /// Copy with the student's answer filled in, for submission.
  QuizAttemptQuestion answeredWith({
    int? selectedOption,
    List<int>? selectedOptions,
    String? submittedText,
  }) {
    return QuizAttemptQuestion(
      questionType: questionType,
      question: question,
      options: options,
      correctOption: correctOption,
      correctOptions: correctOptions,
      correctText: correctText,
      hint: hint,
      explanation: explanation,
      difficultyScore: difficultyScore,
      selectedOption: selectedOption,
      selectedOptions: selectedOptions,
      submittedText: submittedText,
    );
  }

  // SECURITY FIX: this used to send the question's own answer key
  // (correct_option/correct_options/correct_text) back to the server as
  // part of the submission payload, alongside a comment claiming an HMAC
  // signature made this safe - no such signature was ever sent or
  // checked. The backend now stores the real answer key server-side at
  // /generate time (quiz_session_id) and grades every submission against
  // that, never against anything the client reports. This payload is
  // now just the student's own answer - the server doesn't need (and
  // must not trust) anything else here.
  Map<String, dynamic> toAnsweredJson() => {
        'question_type': questionType,
        if (selectedOption != null) 'selected_option': selectedOption,
        if (selectedOptions != null) 'selected_options': selectedOptions,
        if (submittedText != null) 'submitted_text': submittedText,
      };
}

/// A completed quiz attempt with its full per-question breakdown.
class QuizAttemptResult {
  final int id;
  final int? lessonId;
  final int? subjectId;
  final String topic;
  final int totalQuestions;
  final int correctCount;
  final int scorePercent;
  final int? timeTakenSeconds;
  final DateTime createdAt;
  final List<QuizAttemptQuestion> answers;

  QuizAttemptResult({
    required this.id,
    this.lessonId,
    this.subjectId,
    required this.topic,
    required this.totalQuestions,
    required this.correctCount,
    required this.scorePercent,
    this.timeTakenSeconds,
    required this.createdAt,
    required this.answers,
  });

  factory QuizAttemptResult.fromJson(Map<String, dynamic> json) {
    return QuizAttemptResult(
      id: json['id'] as int? ?? 0,
      lessonId: json['lesson_id'] as int?,
      subjectId: json['subject_id'] as int?,
      topic: json['topic'] as String? ?? '',
      totalQuestions: json['total_questions'] as int? ?? 0,
      correctCount: json['correct_count'] as int? ?? 0,
      scorePercent: json['score_percent'] as int? ?? 0,
      timeTakenSeconds: json['time_taken_seconds'] as int?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      answers: (json['answers'] as List<dynamic>? ?? [])
          .map((e) => QuizAttemptQuestion.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One row in quiz history (without the per-question breakdown).
class QuizAttemptSummary {
  final int id;
  final int? lessonId;
  final int? subjectId;
  final String topic;
  final int totalQuestions;
  final int correctCount;
  final int scorePercent;
  final DateTime createdAt;

  QuizAttemptSummary({
    required this.id,
    this.lessonId,
    this.subjectId,
    required this.topic,
    required this.totalQuestions,
    required this.correctCount,
    required this.scorePercent,
    required this.createdAt,
  });

  factory QuizAttemptSummary.fromJson(Map<String, dynamic> json) {
    return QuizAttemptSummary(
      id: json['id'] as int? ?? 0,
      lessonId: json['lesson_id'] as int?,
      subjectId: json['subject_id'] as int?,
      topic: json['topic'] as String? ?? '',
      totalQuestions: json['total_questions'] as int? ?? 0,
      correctCount: json['correct_count'] as int? ?? 0,
      scorePercent: json['score_percent'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// One subject's accuracy row in analytics.
class SubjectAccuracyModel {
  final int subjectId;
  final String subjectName;
  final int attempts;
  final double accuracy;

  SubjectAccuracyModel({
    required this.subjectId,
    required this.subjectName,
    required this.attempts,
    required this.accuracy,
  });

  factory SubjectAccuracyModel.fromJson(Map<String, dynamic> json) {
    return SubjectAccuracyModel(
      subjectId: json['subject_id'] as int? ?? 0,
      subjectName: json['subject_name'] as String? ?? '',
      attempts: json['attempts'] as int? ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// One day's quiz accuracy - used for the weekly performance trend chart.
class DayAccuracyModel {
  final String date;
  final double accuracy;
  final int attempts;

  DayAccuracyModel({required this.date, required this.accuracy, required this.attempts});

  factory DayAccuracyModel.fromJson(Map<String, dynamic> json) {
    return DayAccuracyModel(
      date: json['date'] as String? ?? '',
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      attempts: json['attempts'] as int? ?? 0,
    );
  }
}

/// Quiz performance analytics, computed server-side from real attempts.
class QuizAnalyticsModel {
  final int totalAttempts;
  final double overallAccuracy;
  final int passedCount;
  final int failedCount;
  final double averageScore;
  final int highestScore;
  final List<SubjectAccuracyModel> bySubject;
  final List<SubjectAccuracyModel> weakTopics;
  final List<DayAccuracyModel> weeklyTrend;

  QuizAnalyticsModel({
    required this.totalAttempts,
    required this.overallAccuracy,
    required this.passedCount,
    required this.failedCount,
    required this.averageScore,
    required this.highestScore,
    required this.bySubject,
    required this.weakTopics,
    required this.weeklyTrend,
  });

  factory QuizAnalyticsModel.fromJson(Map<String, dynamic> json) {
    return QuizAnalyticsModel(
      totalAttempts: json['total_attempts'] as int? ?? 0,
      overallAccuracy: (json['overall_accuracy'] as num?)?.toDouble() ?? 0.0,
      passedCount: json['passed_count'] as int? ?? 0,
      failedCount: json['failed_count'] as int? ?? 0,
      averageScore: (json['average_score'] as num?)?.toDouble() ?? 0.0,
      highestScore: json['highest_score'] as int? ?? 0,
      bySubject: (json['by_subject'] as List<dynamic>? ?? [])
          .map((e) => SubjectAccuracyModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      weakTopics: (json['weak_topics'] as List<dynamic>? ?? [])
          .map((e) => SubjectAccuracyModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      weeklyTrend: (json['weekly_trend'] as List<dynamic>? ?? [])
          .map((e) => DayAccuracyModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/models/quiz_attempt_model.dart"), $content_lib_models_quiz_attempt_model_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/models/quiz_attempt_model.dart" -ForegroundColor Green

# --- lib/services/quiz_service.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/services") | Out-Null
$content_lib_services_quiz_service_dart = @'
﻿import '../core/constants/api_constants.dart';
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
  ///
  /// [quizSessionId] MUST be the one returned by [generateQuiz] for this
  /// exact quiz - the backend uses it to look up the real answer key it
  /// stored server-side at generation time and grades against that,
  /// never against anything this client sends. See
  /// QuizAttemptQuestion.toAnsweredJson for why the request no longer
  /// includes an answer key at all.
  Future<QuizAttemptResult> submitFreeformAttempt({
    required String quizSessionId,
    int? subjectId,
    required String topic,
    required List<QuizAttemptQuestion> questions,
    required int timeTakenSeconds,
  }) async {
    final response = await _api.post(ApiConstants.submitFreeformQuizAttempt, {
      'quiz_session_id': quizSessionId,
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
  /// Correct MCQ only if none are given). Returns the quiz_session_id
  /// (required by [submitFreeformAttempt]) alongside the questions - the
  /// questions returned here never include the answer key, only the
  /// student-facing fields (question/options/hint).
  Future<GeneratedQuiz> generateQuiz({
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
    return GeneratedQuiz.fromJson(response['data'] as Map<String, dynamic>);
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/services/quiz_service.dart"), $content_lib_services_quiz_service_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/services/quiz_service.dart" -ForegroundColor Green

# --- lib/screens/quiz/ai_quiz_generator_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/quiz") | Out-Null
$content_lib_screens_quiz_ai_quiz_generator_screen_dart = @'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/quiz_attempt_model.dart';
import '../../models/subject_model.dart';
import '../../services/quiz_service.dart';
import '../../services/subject_service.dart';

/// Lets a student generate a fresh AI quiz on any topic - independent of
/// any specific lesson. Picks a subject (optional, for tagging/analytics),
/// types a topic, chooses difficulty, question types, and question count,
/// then launches QuizScreen in freeform mode.
class AiQuizGeneratorScreen extends StatefulWidget {
  const AiQuizGeneratorScreen({super.key});

  @override
  State<AiQuizGeneratorScreen> createState() => _AiQuizGeneratorScreenState();
}

class _AiQuizGeneratorScreenState extends State<AiQuizGeneratorScreen> {
  final QuizService _quizService = QuizService();
  final SubjectService _subjectService = SubjectService();

  List<SubjectModel> _subjects = [];
  int? _selectedSubjectId;
  String _difficulty = 'medium';
  int _numQuestions = 5;
  final Set<String> _selectedTypes = {QuestionTypes.singleMcq};
  bool _loadingSubjects = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      _subjects = await _subjectService.fetchAllSubjects();
    } catch (_) {
      _subjects = [];
    }
    if (mounted) setState(() => _loadingSubjects = false);
  }

  Future<void> _generate() async {
    if (_selectedSubjectId == null) {
      setState(() => _error = 'Please select a subject.');
      return;
    }
    if (_selectedTypes.isEmpty) {
      setState(() => _error = 'Please select at least one question type.');
      return;
    }

    final subject = _subjects.firstWhere((s) => s.id == _selectedSubjectId);
    final topic = subject.name;

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final generated = await _quizService.generateQuiz(
        subjectId: _selectedSubjectId,
        topic: topic,
        numQuestions: _numQuestions,
        difficulty: _difficulty,
        questionTypes: _selectedTypes.toList(),
      );

      if (generated.questions.isEmpty) {
        if (mounted) {
          setState(() {
            _generating = false;
            _error = 'Could not generate a quiz for that subject. Please try again.';
          });
        }
        return;
      }

      if (mounted) {
        context.push(
          '/quiz',
          extra: {
            'subjectId': _selectedSubjectId,
            'topic': topic,
            'quizSessionId': generated.quizSessionId,
            'freeformQuestions': generated.questions,
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong generating the quiz. Please try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('AI Quiz Generator')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Generate a quiz for any subject', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Pick a subject, question types, and difficulty to get a fresh AI-written quiz.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),

          _sectionCard(
            title: 'Subject',
            child: _loadingSubjects
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<int?>(
                    value: _selectedSubjectId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Select a subject'),
                    items: _subjects.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))).toList(),
                    onChanged: (value) => setState(() => _selectedSubjectId = value),
                  ),
          ),
          const SizedBox(height: 14),

          _sectionCard(
            title: 'Question Types (select one or more)',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: QuestionTypes.all.map((type) {
                final selected = _selectedTypes.contains(type);
                return FilterChip(
                  label: Text(QuestionTypes.label(type), style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    if (value) {
                      _selectedTypes.add(type);
                    } else {
                      _selectedTypes.remove(type);
                    }
                  }),
                  selectedColor: AppColors.purpleLight,
                  checkmarkColor: AppColors.purple,
                  labelStyle: TextStyle(color: selected ? AppColors.purple : AppColors.textSecondary),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          _sectionCard(
            title: 'Difficulty',
            child: Wrap(
              spacing: 8,
              children: ['easy', 'medium', 'hard'].map((d) {
                final selected = _difficulty == d;
                return ChoiceChip(
                  label: Text(d[0].toUpperCase() + d.substring(1)),
                  selected: selected,
                  onSelected: (_) => setState(() => _difficulty = d),
                  selectedColor: AppColors.purpleLight,
                  labelStyle: TextStyle(color: selected ? AppColors.purple : AppColors.textSecondary),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          _sectionCard(
            title: 'Number of Questions: $_numQuestions',
            child: Slider(
              value: _numQuestions.toDouble(),
              min: 3,
              max: 10,
              divisions: 7,
              label: '$_numQuestions',
              activeColor: AppColors.purple,
              onChanged: (value) => setState(() => _numQuestions = value.round()),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _generate,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppColors.purple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _generating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_generating ? 'Generating...' : 'Generate Quiz'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/quiz/ai_quiz_generator_screen.dart"), $content_lib_screens_quiz_ai_quiz_generator_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/quiz/ai_quiz_generator_screen.dart" -ForegroundColor Green

# --- lib/screens/lessons/quiz_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/lessons") | Out-Null
$content_lib_screens_lessons_quiz_screen_dart = @'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ai_content_model.dart';
import '../../models/quiz_attempt_model.dart';
import '../../providers/lesson_provider.dart';
import '../../services/quiz_service.dart';

/// A quiz screen with two modes:
///
/// - Lesson mode (lessonId set, [questions] a List<QuizQuestionModel>):
///   always single-correct MCQ, graded server-side against the lesson's
///   stored answer key. Unchanged from before.
/// - Freeform mode ([freeformQuestions] set, from the AI Quiz Generator):
///   mixes question types (single/multiple MCQ, true/false, fill-blank,
///   short answer) and is graded server-side, keyed by [quizSessionId].
///
/// SECURITY FIX: freeform questions used to arrive from /generate WITH
/// their answer key (correct_option/correct_options/correct_text/
/// explanation) attached, so this screen could grade and show correct/
/// incorrect instantly, client-side, before ever talking to the server.
/// The backend no longer sends that key up front (see quiz_service.dart/
/// quiz_attempt_model.dart) - it's stored server-side against
/// [quizSessionId] and only revealed, per-question, in the grading
/// response after submission. So for freeform mode, every "was this
/// right" / "what was correct" / "explanation" display below now reads
/// from the server's graded answers (_gradedAnswers), never from the
/// pre-submission question list.
class QuizScreen extends StatefulWidget {
  final int? lessonId;
  final int? subjectId;
  final String? topic;
  final String? quizSessionId;
  final List<QuizQuestionModel> questions;
  final List<QuizAttemptQuestion>? freeformQuestions;

  const QuizScreen({
    super.key,
    this.lessonId,
    this.subjectId,
    this.topic,
    this.quizSessionId,
    this.questions = const [],
    this.freeformQuestions,
  });

  bool get isFreeform => freeformQuestions != null;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final QuizService _quizService = QuizService();
  final DateTime _startedAt = DateTime.now();

  // Lesson-mode state (single_mcq only).
  late List<int?> _selected;

  // Freeform-mode state (per question type) - the student's own input only.
  late List<int?> _ffSelectedOption;
  late List<Set<int>> _ffSelectedOptions;
  late List<TextEditingController> _ffTextControllers;

  bool _submitted = false;
  bool _saving = false;
  bool _submitFailed = false;
  String? _saveError;

  /// The server's graded per-question results for freeform mode -
  /// null until the submit response arrives. This (not _ffQuestions) is
  /// the only place correct answers/explanations come from after
  /// submission, since the client never has the answer key beforehand.
  List<QuizAttemptQuestion>? _gradedAnswers;
  int? _gradedCorrectCount;

  List<QuizAttemptQuestion> get _ffQuestions => widget.freeformQuestions ?? [];

  @override
  void initState() {
    super.initState();
    _selected = List<int?>.filled(widget.questions.length, null);
    _ffSelectedOption = List<int?>.filled(_ffQuestions.length, null);
    _ffSelectedOptions = List.generate(_ffQuestions.length, (_) => <int>{});
    _ffTextControllers = List.generate(_ffQuestions.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _ffTextControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _allAnswered {
    if (widget.isFreeform) {
      for (var i = 0; i < _ffQuestions.length; i++) {
        final q = _ffQuestions[i];
        switch (q.questionType) {
          case QuestionTypes.multipleMcq:
            if (_ffSelectedOptions[i].isEmpty) return false;
            break;
          case QuestionTypes.fillBlank:
          case QuestionTypes.shortAnswer:
            if (_ffTextControllers[i].text.trim().isEmpty) return false;
            break;
          default:
            if (_ffSelectedOption[i] == null) return false;
        }
      }
      return true;
    }
    return _selected.every((s) => s != null);
  }

  int get _correctCount {
    if (widget.isFreeform) {
      // Not known until the server grades it - see _gradedAnswers.
      return _gradedCorrectCount ?? 0;
    }
    int count = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      if (_selected[i] == widget.questions[i].correctOption) count++;
    }
    return count;
  }

  /// The question data to use for displaying correctness/explanation for
  /// freeform question [i]: the server's graded answer once available,
  /// otherwise the original (answer-key-free) question.
  QuizAttemptQuestion _displayQuestion(int i) {
    if (_gradedAnswers != null && i < _gradedAnswers!.length) {
      return _gradedAnswers![i];
    }
    return _ffQuestions[i];
  }

  bool? _isFreeformCorrect(int i) {
    if (_gradedAnswers == null || i >= _gradedAnswers!.length) return null;
    return _gradedAnswers![i].isCorrect;
  }

  int get _totalQuestions => widget.isFreeform ? _ffQuestions.length : widget.questions.length;
  int get _elapsedSeconds => DateTime.now().difference(_startedAt).inSeconds;

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _saving = true;
      _saveError = null;
      _submitFailed = false;
    });

    if (!widget.isFreeform && widget.lessonId != null) {
      final scorePercent = ((_correctCount / widget.questions.length) * 100).round();
      await context.read<LessonProvider>().markCompleted(widget.lessonId!, score: scorePercent);
    }

    try {
      if (widget.isFreeform) {
        if (widget.quizSessionId == null || widget.quizSessionId!.isEmpty) {
          // Shouldn't happen from the normal generator flow, but fail
          // loudly rather than submitting something the server will
          // just reject anyway.
          throw StateError('Missing quiz session - please generate a new quiz.');
        }
        final answered = List.generate(_ffQuestions.length, (i) {
          final q = _ffQuestions[i];
          return q.answeredWith(
            selectedOption: _ffSelectedOption[i],
            selectedOptions: q.questionType == QuestionTypes.multipleMcq ? _ffSelectedOptions[i].toList() : null,
            submittedText: (q.questionType == QuestionTypes.fillBlank || q.questionType == QuestionTypes.shortAnswer)
                ? _ffTextControllers[i].text.trim()
                : null,
          );
        });
        final result = await _quizService.submitFreeformAttempt(
          quizSessionId: widget.quizSessionId!,
          subjectId: widget.subjectId,
          topic: widget.topic ?? 'General',
          timeTakenSeconds: _elapsedSeconds,
          questions: answered,
        );
        _gradedAnswers = result.answers;
        _gradedCorrectCount = result.correctCount;
      } else if (widget.lessonId != null) {
        await _quizService.submitLessonAttempt(
          lessonId: widget.lessonId!,
          answers: _selected.map((s) => s ?? -1).toList(),
          timeTakenSeconds: _elapsedSeconds,
        );
      }
    } catch (e) {
      _saveError = widget.isFreeform
          ? 'Could not grade your quiz - the session may have expired. Please generate a new quiz and try again.'
          : 'Your score is shown below, but saving to history failed. Check your connection.';
      _submitFailed = widget.isFreeform; // freeform has no local score to fall back on
    }

    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final showScore = !widget.isFreeform || (!_saving && !_submitFailed);
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_submitted) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _submitFailed ? const Color(0xFFFFE5E5) : AppColors.greenLight,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Icon(
                    _submitFailed ? Icons.error_outline_rounded : Icons.emoji_events_rounded,
                    color: _submitFailed ? AppColors.error : AppColors.green,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  if (_saving)
                    const Text('Grading your quiz...', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
                  else if (showScore)
                    Text(
                      'You scored $_correctCount / $_totalQuestions',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.green),
                    ),
                ],
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 10),
              Text(_saveError!, style: const TextStyle(color: AppColors.error, fontSize: 12), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
          ],
          if (widget.isFreeform)
            for (var i = 0; i < _ffQuestions.length; i++) _buildFreeformQuestion(i)
          else
            for (var i = 0; i < widget.questions.length; i++) _buildLessonQuestion(i),
          const SizedBox(height: 12),
          if (!_submitted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _allAnswered ? _submit : null,
                child: const Text('Submit Quiz'),
              ),
            )
          else if (_submitFailed)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
            ),
        ],
      ),
    );
  }

  // --- Lesson mode (single_mcq only, unchanged - server-graded via the
  // lesson's own stored answer key, never sent to the client) ---

  Widget _buildLessonQuestion(int index) {
    final q = widget.questions[index];
    return _questionCard(
      index: index,
      questionText: q.question,
      child: Column(children: [for (var j = 0; j < q.options.length; j++) _buildLessonOption(index, j, q)]),
    );
  }

  Widget _buildLessonOption(int qIndex, int optionIndex, QuizQuestionModel q) {
    final selected = _selected[qIndex] == optionIndex;
    var bg = AppColors.pageBackground;
    var fg = AppColors.textPrimary;

    if (_submitted) {
      if (optionIndex == q.correctOption) {
        bg = AppColors.greenLight;
        fg = AppColors.green;
      } else if (selected) {
        bg = const Color(0xFFFFE5E5);
        fg = AppColors.error;
      }
    } else if (selected) {
      bg = AppColors.purpleLight;
      fg = AppColors.purple;
    }

    return _optionTile(
      label: q.options[optionIndex],
      bg: bg,
      fg: fg,
      selected: selected,
      onTap: _submitted ? null : () => setState(() => _selected[qIndex] = optionIndex),
    );
  }

  // --- Freeform mode (multi-type, server-graded) ---

  Widget _buildFreeformQuestion(int index) {
    final displayQ = _submitted ? _displayQuestion(index) : _ffQuestions[index];
    final original = _ffQuestions[index];
    Widget answerWidget;
    switch (original.questionType) {
      case QuestionTypes.multipleMcq:
        answerWidget = Column(children: [for (var j = 0; j < original.options.length; j++) _buildMultiOption(index, j, displayQ)]);
        break;
      case QuestionTypes.fillBlank:
      case QuestionTypes.shortAnswer:
        answerWidget = _buildTextAnswer(index, displayQ);
        break;
      default:
        answerWidget = Column(children: [for (var j = 0; j < original.options.length; j++) _buildSingleOption(index, j, displayQ)]);
    }

    // Grading (correctOption/explanation) only exists on displayQ once
    // the server has responded - before/without that, show neither.
    final graded = _submitted && _gradedAnswers != null;

    return _questionCard(
      index: index,
      questionText: original.question,
      typeLabel: QuestionTypes.label(original.questionType),
      difficultyScore: original.difficultyScore,
      hint: original.hint,
      explanation: graded ? displayQ.explanation : null,
      child: answerWidget,
    );
  }

  Widget _buildSingleOption(int qIndex, int optionIndex, QuizAttemptQuestion gradedOrOriginal) {
    final selected = _ffSelectedOption[qIndex] == optionIndex;
    final graded = _submitted && _gradedAnswers != null;
    var bg = AppColors.pageBackground;
    var fg = AppColors.textPrimary;

    if (graded) {
      if (optionIndex == gradedOrOriginal.correctOption) {
        bg = AppColors.greenLight;
        fg = AppColors.green;
      } else if (selected) {
        bg = const Color(0xFFFFE5E5);
        fg = AppColors.error;
      }
    } else if (selected) {
      bg = AppColors.purpleLight;
      fg = AppColors.purple;
    }

    return _optionTile(
      label: gradedOrOriginal.options.isNotEmpty ? gradedOrOriginal.options[optionIndex] : _ffQuestions[qIndex].options[optionIndex],
      bg: bg,
      fg: fg,
      selected: selected,
      onTap: _submitted ? null : () => setState(() => _ffSelectedOption[qIndex] = optionIndex),
    );
  }

  Widget _buildMultiOption(int qIndex, int optionIndex, QuizAttemptQuestion gradedOrOriginal) {
    final selected = _ffSelectedOptions[qIndex].contains(optionIndex);
    final graded = _submitted && _gradedAnswers != null;
    final isCorrectOption = (gradedOrOriginal.correctOptions ?? []).contains(optionIndex);
    var bg = AppColors.pageBackground;
    var fg = AppColors.textPrimary;

    if (graded) {
      if (isCorrectOption) {
        bg = AppColors.greenLight;
        fg = AppColors.green;
      } else if (selected) {
        bg = const Color(0xFFFFE5E5);
        fg = AppColors.error;
      }
    } else if (selected) {
      bg = AppColors.purpleLight;
      fg = AppColors.purple;
    }

    return _optionTile(
      label: _ffQuestions[qIndex].options[optionIndex],
      bg: bg,
      fg: fg,
      selected: selected,
      leading: Icon(
        selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        size: 18,
        color: selected ? AppColors.purple : AppColors.textSecondary,
      ),
      onTap: _submitted
          ? null
          : () => setState(() {
                if (selected) {
                  _ffSelectedOptions[qIndex].remove(optionIndex);
                } else {
                  _ffSelectedOptions[qIndex].add(optionIndex);
                }
              }),
    );
  }

  Widget _buildTextAnswer(int qIndex, QuizAttemptQuestion gradedOrOriginal) {
    final graded = _submitted && _gradedAnswers != null;
    final isCorrect = graded ? _isFreeformCorrect(qIndex) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ffTextControllers[qIndex],
          enabled: !_submitted,
          decoration: InputDecoration(
            hintText: gradedOrOriginal.questionType == QuestionTypes.fillBlank ? 'Fill in the blank...' : 'Type your answer...',
            filled: true,
            fillColor: AppColors.pageBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (graded && isCorrect != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 16, color: isCorrect ? AppColors.green : AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Correct answer: ${gradedOrOriginal.correctText ?? ''}',
                  style: TextStyle(fontSize: 12, color: isCorrect ? AppColors.green : AppColors.error),
                ),
              ),
            ],
          ),
        ] else if (_submitted && !_saving) ...[
          const SizedBox(height: 8),
          const Text('Grading...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ],
    );
  }

  Widget _optionTile({
    required String label,
    required Color bg,
    required Color fg,
    required bool selected,
    Widget? leading,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 10)],
              Expanded(
                child: Text(label, style: TextStyle(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionCard({
    required int index,
    required String questionText,
    required Widget child,
    String? typeLabel,
    int? difficultyScore,
    String? hint,
    String? explanation,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (typeLabel != null || difficultyScore != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                children: [
                  if (typeLabel != null) _tag(typeLabel, AppColors.blueLight, AppColors.blue),
                  if (difficultyScore != null) _tag('Difficulty $difficultyScore/10', AppColors.orangeLight, AppColors.orange),
                ],
              ),
            ),
          Text('Q${index + 1}. $questionText', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          if (hint != null && hint.isNotEmpty && !_submitted) ...[
            const SizedBox(height: 6),
            _HintReveal(hint: hint),
          ],
          const SizedBox(height: 10),
          child,
          if (_submitted && explanation != null && explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(10)),
              child: Text('Explanation: $explanation', style: const TextStyle(fontSize: 12, color: AppColors.purple)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _HintReveal extends StatefulWidget {
  final String hint;
  const _HintReveal({required this.hint});

  @override
  State<_HintReveal> createState() => _HintRevealState();
}

class _HintRevealState extends State<_HintReveal> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    if (_shown) {
      return Text('Hint: ${widget.hint}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic));
    }
    return InkWell(
      onTap: () => setState(() => _shown = true),
      child: const Text('Show hint', style: TextStyle(fontSize: 12, color: AppColors.purple, fontWeight: FontWeight.w600)),
    );
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/lessons/quiz_screen.dart"), $content_lib_screens_lessons_quiz_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/lessons/quiz_screen.dart" -ForegroundColor Green

# --- lib/core/routes/app_router.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/core/routes") | Out-Null
$content_lib_core_routes_app_router_dart = @'
import 'package:go_router/go_router.dart';
import '../../models/ai_content_model.dart';
import '../../models/quiz_attempt_model.dart';
import '../../providers/auth_provider.dart';
import '../../screens/ai/ai_tutor_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/teacher_apply_screen.dart';
import '../../screens/categories/categories_screen.dart';
import '../../screens/dashboard/dashboard_screen.dart';
import '../../screens/lessons/lesson_player_screen.dart';
import '../../screens/lessons/lessons_screen.dart';
import '../../screens/lessons/pdf_viewer_screen.dart';
import '../../screens/lessons/quiz_screen.dart';
import '../../screens/quiz/ai_quiz_generator_screen.dart';
import '../../screens/quiz/progress_dashboard_screen.dart';
import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/admin/teacher_applications_screen.dart';
import '../../screens/admin/admin_assignments_screen.dart';
import '../../screens/assignments/create_assignment_screen.dart';
import '../../screens/assignments/my_assignments_screen.dart';
import '../../screens/assignments/submission_review_screen.dart';
import '../../screens/assignments/assignment_list_screen.dart';
import '../../screens/assignments/assignment_detail_screen.dart';
import '../../screens/liveclass/create_live_class_screen.dart';
import '../../screens/liveclass/my_live_classes_screen.dart';
import '../../screens/liveclass/student_live_classes_screen.dart';
import '../../screens/liveclass/admin_live_classes_screen.dart';
import '../../screens/notifications/notification_center_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/splash/splash_screen.dart';
import '../../screens/subjects/subjects_screen.dart';

/// Centralized GoRouter config with a redirect guard: unauthenticated users
/// are bounced to /login, authenticated users away from /login /register.
///
/// Day 2 routes (categories/subjects/lessons/player/pdf-viewer/search) all
/// sit "on top of" the authenticated area - none are reachable from
/// /login or /register, matching the Dashboard -> Categories -> ... flow.
class AppRouter {
  final AuthProvider authProvider;

  AppRouter(this.authProvider);

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    // QA fix ("Router rebuild issue"): was `refreshListenable:
    // authProvider` - every notifyListeners() on AuthProvider (including
    // ones only toggling a loading spinner, unrelated to auth status)
    // triggered a full router redirect re-evaluation. statusNotifier
    // only fires when authProvider.status itself actually changes.
    refreshListenable: authProvider.statusNotifier,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/teacher-apply', builder: (context, state) => const TeacherApplyScreen()),
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),

      // --- Day 2: Course & Learning Management ---
      GoRoute(
        path: '/categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/subjects',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SubjectsScreen(
            categoryId: extra['categoryId'] as int? ?? 0,
            categoryName: extra['categoryName'] as String? ?? 'Subjects',
          );
        },
      ),
      GoRoute(
        path: '/lessons',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return LessonsScreen(
            subjectId: extra['subjectId'] as int? ?? 0,
            subjectName: extra['subjectName'] as String? ?? 'Lessons',
          );
        },
      ),
      GoRoute(
        path: '/lesson-player',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return LessonPlayerScreen(lessonId: extra['lessonId'] as int? ?? 0);
        },
      ),
      GoRoute(
        path: '/pdf-viewer',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PdfViewerScreen(
            url: extra['url'] as String? ?? '',
            title: extra['title'] as String? ?? 'Notes',
          );
        },
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/quiz',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return QuizScreen(
            lessonId: extra['lessonId'] as int?,
            subjectId: extra['subjectId'] as int?,
            topic: extra['topic'] as String?,
            quizSessionId: extra['quizSessionId'] as String?,
            questions: (extra['questions'] as List<dynamic>? ?? []).cast<QuizQuestionModel>(),
            freeformQuestions: (extra['freeformQuestions'] as List<dynamic>?)?.cast<QuizAttemptQuestion>(),
          );
        },
      ),
      GoRoute(
        path: '/ai-quiz-generator',
        builder: (context, state) => const AiQuizGeneratorScreen(),
      ),
      GoRoute(
        path: '/quiz-analytics',
        builder: (context, state) => const ProgressDashboardScreen(),
      ),
      GoRoute(
        path: '/admin-dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin-teacher-applications',
        builder: (context, state) => const TeacherApplicationsScreen(),
      ),
      GoRoute(
        path: '/admin-assignments',
        builder: (context, state) => const AdminAssignmentsScreen(),
      ),
      GoRoute(
        path: '/create-assignment',
        builder: (context, state) => const CreateAssignmentScreen(),
      ),
      GoRoute(
        path: '/my-assignments',
        builder: (context, state) => const MyAssignmentsScreen(),
      ),
      GoRoute(
        path: '/assignment-submissions',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          // QA fix ("Fix route parameter null crashes"): was `as int`
          // with no fallback - if extra didn't contain assignmentId (a
          // stale deep link, a caller forgetting to pass extra, etc.)
          // this threw a null-cast exception and crashed the app. Now
          // consistent with every other route in this file.
          return SubmissionReviewScreen(
            assignmentId: extra['assignmentId'] as int? ?? 0,
            title: extra['title'] as String? ?? 'Assignment',
          );
        },
      ),
      GoRoute(
        path: '/subject-assignments',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          // QA fix - same as above.
          return AssignmentListScreen(
            subjectId: extra['subjectId'] as int? ?? 0,
            subjectName: extra['subjectName'] as String? ?? 'Subject',
          );
        },
      ),
      GoRoute(
        path: '/assignment-detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          // QA fix - same as above.
          return AssignmentDetailScreen(assignmentId: extra['assignmentId'] as int? ?? 0);
        },
      ),
      GoRoute(
        path: '/create-live-class',
        builder: (context, state) => const CreateLiveClassScreen(),
      ),
      GoRoute(
        path: '/my-live-classes',
        builder: (context, state) => const MyLiveClassesScreen(),
      ),
      GoRoute(
        path: '/student-live-classes',
        builder: (context, state) => const StudentLiveClassesScreen(),
      ),
      GoRoute(
        path: '/admin-live-classes',
        builder: (context, state) => const AdminLiveClassesScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationCenterScreen(),
      ),

      // --- AI Tutor: single ChatGPT-style screen (chat + history drawer +
      // recommendations + homework mode, all in one) ---
      GoRoute(path: '/ai-tutor', builder: (context, state) => const AiTutorScreen()),
    ],
    // Routing fix ("Invalid Routes"): GoRouter's default error screen for
    // an unknown path is a bare, unstyled error page. This redirects any
    // unmatched route straight to the dashboard instead of showing that.
    errorBuilder: (context, state) => const DashboardScreen(),
    redirect: (context, state) {
      final status = authProvider.status;
      final loggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/teacher-apply';
      final onSplash = state.matchedLocation == '/';

      if (status == AuthStatus.unknown) {
        return onSplash ? null : '/';
      }
      if (status == AuthStatus.unauthenticated) {
        return loggingIn ? null : '/login';
      }
      if (status == AuthStatus.authenticated && (loggingIn || onSplash)) {
        return '/dashboard';
      }

      // Routing fix ("Role-based Routing"): admin-only and teacher-only
      // routes previously had no guard at the router level at all - only
      // the Profile screen's conditional tiles kept most users from ever
      // tapping into them, but a stray deep link or button reaching one
      // directly (e.g. a student navigating to /admin-dashboard) would
      // land them on a real screen that then just failed its admin-only
      // API calls with 403s, instead of being redirected cleanly.
      final role = authProvider.currentUser?.role;
      final isAdminRoute = state.matchedLocation.startsWith('/admin-');
      if (isAdminRoute && role != 'admin') {
        return '/dashboard';
      }
      const teacherOnlyRoutes = {'/create-assignment', '/create-live-class'};
      if (teacherOnlyRoutes.contains(state.matchedLocation) && role != 'teacher' && role != 'admin') {
        return '/dashboard';
      }

      return null;
    },
  );
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/core/routes/app_router.dart"), $content_lib_core_routes_app_router_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/core/routes/app_router.dart" -ForegroundColor Green

# --- lib/screens/liveclass/live_class_room_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/liveclass") | Out-Null
$content_lib_screens_liveclass_live_class_room_screen_dart = @'
﻿import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../models/assignment_model.dart';
import '../../models/live_class_model.dart';
import '../../services/assignment_service.dart';
import '../../services/live_class_service.dart';
import '../assignments/assignment_detail_screen.dart';
import 'resource_pdf_viewer_screen.dart';
import 'resource_image_viewer_screen.dart';
import 'resource_video_viewer_screen.dart';

/// Real video call screen backed by LiveKit - modern classroom UI with
/// full-screen primary video, floating draggable self-view, a minimal
/// toolbar + More menu, slide-up panels (Chat/Participants/Raised Hands/
/// Class Info/Attachments), pinned announcements, and in-meeting toasts.
///
/// Chat, announcements, and raise-hand all ride on LiveKit's data channel
/// (publishData/DataReceivedEvent) - no new backend, so none of it
/// persists after the call ends. Attachments reuses the EXISTING
/// AssignmentService (real data, no new backend). Message "Sent" only
/// means it was published locally - there's no delivery-receipt protocol
/// over a data channel, so no "Delivered"/"Read" state is shown (that
/// would be dishonest without a real ack mechanism).
class LiveClassRoomScreen extends StatefulWidget {
  final int classId;
  final String url;
  final String token;
  final String classTitle;
  final bool isTeacher;
  final String subjectName;
  final String lessonTitle;
  final String description;
  final int? subjectId;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final Future<void> Function()? onEndClass;

  const LiveClassRoomScreen({
    super.key,
    required this.classId,
    required this.url,
    required this.token,
    required this.classTitle,
    required this.isTeacher,
    this.subjectName = '',
    this.lessonTitle = '',
    this.description = '',
    this.subjectId,
    this.scheduledStart,
    this.scheduledEnd,
    this.onEndClass,
  });

  @override
  State<LiveClassRoomScreen> createState() => _LiveClassRoomScreenState();
}

class _ChatMessage {
  final String id;
  final String identity;
  final String name;
  final String text;
  final DateTime time;
  final bool isTeacher;
  _ChatMessage({required this.id, required this.identity, required this.name, required this.text, required this.time, required this.isTeacher});
}

class _Announcement {
  final String id;
  final String text;
  final String teacherName;
  final DateTime time;
  _Announcement({required this.id, required this.text, required this.teacherName, required this.time});
}

enum _SidePanel { none, chat, participants, raiseQueue, classInfo, attachments }

class _Stroke {
  final String id;
  final List<Offset> points;
  final Color color;
  final double width;
  _Stroke({required this.id, required this.points, required this.color, required this.width});
}

class _LiveClassRoomScreenState extends State<LiveClassRoomScreen> {
  late final lk.Room _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  final LiveClassService _classService = LiveClassService();
  final AssignmentService _assignmentService = AssignmentService();

  bool _connecting = true;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _switchingCamera = false;
  lk.CameraPosition _cameraPosition = lk.CameraPosition.front;
  String? _error;

  bool _speakerView = true;
  bool _speakerphoneOn = true;
  bool _roomLocked = false;

  // Teacher Pin Mode (default ON - teacher is always the large video until
  // they manually unpin), Spotlight (teacher highlights a specific
  // student, overrides pin), and tap-to-highlight (only takes effect when
  // not pinned/spotlighted).
  bool _teacherPinned = true;
  String? _spotlightIdentity;
  String? _manualPrimaryIdentity;

  // Screen share: uses LiveKit's built-in screen capture - no backend
  // needed, it's just another video track on the same room/token.
  bool _screenSharing = false;

  // Whiteboard: strokes ride on the LiveKit data channel (like chat) -
  // ephemeral, resets when the call ends, and doesn't sync to students
  // who join mid-drawing (they see it fill in from that point on).
  bool _whiteboardOpen = false;
  final List<_Stroke> _whiteboardStrokes = [];
  List<Offset> _currentStrokePoints = [];
  Color _whiteboardColor = Colors.red;
  double _whiteboardStrokeWidth = 4;

  Timer? _fallbackRebuildTimer;
  Timer? _endingSoonTimer;
  bool _endingSoonNotified = false;

  Set<String> _activeSpeakerIdentities = {};
  final Map<String, lk.ConnectionQuality> _connectionQuality = {};

  int _msgCounter = 0;
  final List<_ChatMessage> _chatMessages = [];
  int _unreadChatCount = 0;
  bool _chatSearchOpen = false;
  final TextEditingController _chatSearchController = TextEditingController();

  final List<_Announcement> _announcements = [];

  // identity -> time raised (queue order + "raised Xm ago" display)
  final Map<String, DateTime> _raisedHandsAt = {};
  bool _localHandRaised = false;

  _SidePanel _sidePanel = _SidePanel.none;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  List<AssignmentModel> _attachments = [];
  List<ClassResourceModel> _resources = [];
  bool _loadingAttachments = false;
  bool _uploadingResource = false;
  double _uploadProgress = 0;
  String? _attachmentsError;

  Offset _pipOffset = const Offset(16, 90);

  @override
  void initState() {
    super.initState();
    _room = lk.Room();
    _connect();
    _startEndingSoonWatcher();
  }

  void _startEndingSoonWatcher() {
    if (widget.scheduledEnd == null) return;
    _endingSoonTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_endingSoonNotified) return;
      final remaining = widget.scheduledEnd!.difference(DateTime.now());
      if (remaining.inMinutes <= 5 && remaining.inSeconds > 0) {
        _endingSoonNotified = true;
        _showToast('Class ending in about ${remaining.inMinutes} minute${remaining.inMinutes == 1 ? '' : 's'}');
      }
    });
  }

  Future<void> _connect() async {
    try {
      final statuses = await [Permission.camera, Permission.microphone].request();
      final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
      if (!cameraGranted || !micGranted) {
        if (mounted) setState(() {
          _connecting = false;
          _error = 'Camera and microphone access are required to join a live class. Please allow them in your device settings.';
        });
        return;
      }

      _listener = _room.createListener();
      _listener!
        ..on<lk.ParticipantConnectedEvent>((event) {
          setState(() {});
          _showToast('${event.participant.name.isNotEmpty ? event.participant.name : event.participant.identity} joined');
        })
        ..on<lk.ParticipantDisconnectedEvent>((event) {
          setState(() {
            if (_spotlightIdentity == event.participant.identity) _spotlightIdentity = null;
            if (_manualPrimaryIdentity == event.participant.identity) _manualPrimaryIdentity = null;
          });
          _showToast('${event.participant.name.isNotEmpty ? event.participant.name : event.participant.identity} left');
        })
        ..on<lk.TrackSubscribedEvent>((_) => setState(() {}))
        ..on<lk.TrackUnsubscribedEvent>((_) => setState(() {}))
        ..on<lk.TrackPublishedEvent>((_) => setState(() {}))
        ..on<lk.TrackUnpublishedEvent>((_) => setState(() {}))
        ..on<lk.TrackMutedEvent>((_) => setState(() {}))
        ..on<lk.TrackUnmutedEvent>((_) => setState(() {}))
        ..on<lk.LocalTrackPublishedEvent>((_) => setState(() {}))
        ..on<lk.LocalTrackUnpublishedEvent>((_) => setState(() {}))
        ..on<lk.ActiveSpeakersChangedEvent>((event) {
          setState(() => _activeSpeakerIdentities = event.speakers.map((p) => p.identity).toSet());
        })
        ..on<lk.ParticipantConnectionQualityUpdatedEvent>((event) {
          setState(() => _connectionQuality[event.participant.identity] = event.connectionQuality);
        })
        ..on<lk.DataReceivedEvent>((event) => _handleDataReceived(event))
        ..on<lk.RoomDisconnectedEvent>((_) {
          // Auto Exit: a single pop() could land on an intermediate
          // screen (e.g. the Waiting Room) instead of the Live Classes
          // list. Popping all the way back to the first route in this
          // flow guarantees the student always lands back on Live
          // Classes automatically, whether the teacher ended the class
          // or the connection simply dropped.
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });

      _fallbackRebuildTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });

      await _room.connect(
        widget.url,
        widget.token,
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );
      await _room.localParticipant?.setCameraEnabled(true);
      await _room.localParticipant?.setMicrophoneEnabled(true);

      if (mounted) setState(() => _connecting = false);
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[LiveClassRoom] Connection failed: $e');
      // ignore: avoid_print
      print(stackTrace);
      if (mounted) setState(() {
        _connecting = false;
        _error = 'Could not connect to the class. Please check your connection and try again.';
      });
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.grey.shade900,
        margin: const EdgeInsets.only(bottom: 100, left: 60, right: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  String _newMsgId() {
    _msgCounter++;
    final identity = _room.localParticipant?.identity ?? 'local';
    return '$identity-${DateTime.now().millisecondsSinceEpoch}-$_msgCounter';
  }

  // --- Data channel: chat, delete, announcements, raise hand ---

  void _handleDataReceived(lk.DataReceivedEvent event) {
    try {
      final decoded = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      final identity = decoded['identity'] as String? ?? '';
      final localIdentity = _room.localParticipant?.identity ?? '';

      switch (type) {
        case 'chat':
          if (identity == localIdentity) return;
          setState(() {
            _chatMessages.add(_ChatMessage(
              id: decoded['id'] as String? ?? _newMsgId(),
              identity: identity,
              name: decoded['name'] as String? ?? 'Unknown',
              text: decoded['text'] as String? ?? '',
              time: DateTime.tryParse(decoded['ts'] as String? ?? '') ?? DateTime.now(),
              isTeacher: identity.startsWith('teacher-'),
            ));
            if (_sidePanel != _SidePanel.chat) _unreadChatCount++;
          });
          _scrollChatToBottom();
          break;

        case 'chat_delete':
          final msgId = decoded['id'] as String? ?? '';
          setState(() => _chatMessages.removeWhere((m) => m.id == msgId));
          break;

        case 'announcement':
          setState(() {
            _announcements.add(_Announcement(
              id: decoded['id'] as String? ?? _newMsgId(),
              text: decoded['text'] as String? ?? '',
              teacherName: decoded['name'] as String? ?? 'Teacher',
              time: DateTime.now(),
            ));
          });
          _showToast('\u{1F4E2} New announcement');
          break;

        case 'announcement_remove':
          final annId = decoded['id'] as String? ?? '';
          setState(() => _announcements.removeWhere((a) => a.id == annId));
          break;

        case 'raise_hand':
          final raised = decoded['raised'] as bool? ?? false;
          setState(() {
            if (raised) {
              _raisedHandsAt[identity] = DateTime.now();
              if (widget.isTeacher) _showToast('${decoded['name'] as String? ?? 'A student'} raised their hand');
            } else {
              _raisedHandsAt.remove(identity);
            }
          });
          break;

        case 'hand_lowered_by_teacher':
          // Sent by the teacher targeting a specific student's identity.
          if (identity == localIdentity) {
            setState(() => _localHandRaised = false);
            _showToast('The teacher lowered your hand');
          }
          setState(() => _raisedHandsAt.remove(identity));
          break;

        case 'hand_accepted':
          if (identity == localIdentity) _showToast('The teacher acknowledged your raised hand');
          break;

        case 'hands_cleared':
          setState(() {
            _raisedHandsAt.clear();
            _localHandRaised = false;
          });
          break;

        case 'whiteboard_open':
          setState(() => _whiteboardOpen = true);
          break;

        case 'whiteboard_close':
          setState(() => _whiteboardOpen = false);
          break;

        case 'whiteboard_stroke':
          final pointsRaw = decoded['points'] as List<dynamic>? ?? [];
          setState(() {
            _whiteboardStrokes.add(_Stroke(
              id: decoded['id'] as String? ?? _newMsgId(),
              points: pointsRaw.map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList(),
              color: Color(decoded['color'] as int? ?? Colors.red.value),
              width: (decoded['width'] as num?)?.toDouble() ?? 4,
            ));
          });
          break;

        case 'whiteboard_clear':
          setState(() => _whiteboardStrokes.clear());
          break;

        case 'whiteboard_undo':
          setState(() {
            if (_whiteboardStrokes.isNotEmpty) _whiteboardStrokes.removeLast();
          });
          break;

        case 'resource_shared':
          if (identity != localIdentity) {
            _showToast('\u{1F4CE} ${decoded['name'] as String? ?? 'A file'} was shared');
          }
          break;
      }
    } catch (_) {
      // Ignore malformed/unknown data messages from other clients/versions.
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(_chatScrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _publish(Map<String, dynamic> payload) async {
    try {
      await _room.localParticipant?.publishData(utf8.encode(jsonEncode(payload)));
    } catch (_) {}
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || text.length > 500) return;
    final local = _room.localParticipant;
    final identity = local?.identity ?? '';
    final name = local?.name.isNotEmpty == true ? local!.name : identity;
    final id = _newMsgId();

    setState(() {
      _chatMessages.add(_ChatMessage(id: id, identity: identity, name: name, text: text, time: DateTime.now(), isTeacher: widget.isTeacher));
    });
    _chatController.clear();
    _scrollChatToBottom();

    await _publish({'type': 'chat', 'id': id, 'identity': identity, 'name': name, 'text': text, 'ts': DateTime.now().toIso8601String()});
  }

  void _deleteMessage(_ChatMessage m) {
    final localIdentity = _room.localParticipant?.identity ?? '';
    final canDelete = widget.isTeacher || m.identity == localIdentity;
    if (!canDelete) return;
    setState(() => _chatMessages.removeWhere((msg) => msg.id == m.id));
    _publish({'type': 'chat_delete', 'id': m.id, 'identity': localIdentity});
  }

  Future<void> _postAnnouncement() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Post Announcement', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 200,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Message all students...', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Post')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;

    final local = _room.localParticipant;
    final name = local?.name.isNotEmpty == true ? local!.name : 'Teacher';
    final id = _newMsgId();
    setState(() => _announcements.add(_Announcement(id: id, text: text, teacherName: name, time: DateTime.now())));
    await _publish({'type': 'announcement', 'id': id, 'identity': local?.identity ?? '', 'name': name, 'text': text});
  }

  void _removeAnnouncement(_Announcement a) {
    setState(() => _announcements.removeWhere((x) => x.id == a.id));
    _publish({'type': 'announcement_remove', 'id': a.id, 'identity': _room.localParticipant?.identity ?? ''});
  }

  Future<void> _toggleRaiseHand() async {
    final local = _room.localParticipant;
    final identity = local?.identity ?? '';
    final name = local?.name.isNotEmpty == true ? local!.name : identity;
    final newState = !_localHandRaised;

    setState(() {
      _localHandRaised = newState;
      if (newState) {
        _raisedHandsAt[identity] = DateTime.now();
      } else {
        _raisedHandsAt.remove(identity);
      }
    });

    await _publish({'type': 'raise_hand', 'identity': identity, 'name': name, 'raised': newState});
  }

  Future<void> _acceptHand(String identity) async {
    await _publish({'type': 'hand_accepted', 'identity': identity});
    if (mounted) setState(() => _raisedHandsAt.remove(identity));
  }

  Future<void> _lowerHand(String identity) async {
    await _publish({'type': 'hand_lowered_by_teacher', 'identity': identity});
    if (mounted) setState(() => _raisedHandsAt.remove(identity));
  }

  Future<void> _clearAllHands() async {
    await _publish({'type': 'hands_cleared', 'identity': _room.localParticipant?.identity ?? ''});
    if (mounted) setState(() => _raisedHandsAt.clear());
  }

  // --- Screen Share (LiveKit built-in - no backend, just another track) ---

  static const _screenShareChannel = MethodChannel('ai_tutor_app/screen_share');
  bool _screenShareBusy = false;

  Future<void> _toggleScreenShare() async {
    if (_screenShareBusy) return; // ignore taps while a toggle is in flight
    _screenShareBusy = true;
    try {
      final newState = !_screenSharing;

      if (newState) {
        // The LiveKit-documented, Android-verified correct sequence:
        // https://docs.livekit.io/transport/media/screenshare/ -
        // "Before starting the background service and enabling screen
        // share, you MUST call Helper.requestCapturePermission() from
        // flutter_webrtc, and only proceed if it returns true."
        //
        // Calling setScreenShareEnabled() directly (without this step)
        // bundles "ask permission" and "start capturing" into one native
        // call - flutter_webrtc's getDisplayMedia() calls
        // MediaProjectionManager.getMediaProjection() immediately after
        // the permission dialog closes, which crashes with
        // "Media projections require a foreground service of type
        // ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION" because
        // our foreground service isn't running yet at that instant.
        //
        // Correct order: request permission only (Helper) -> start our
        // foreground service -> THEN call setScreenShareEnabled, which
        // now succeeds because both Android requirements (permission
        // granted, service running) are already satisfied.
        final granted = await webrtc.Helper.requestCapturePermission();
        if (!granted) {
          _showToast('Screen recording permission is required to share your screen.');
          return;
        }

        await _screenShareChannel.invokeMethod('startScreenShareService');
        await Future.delayed(const Duration(milliseconds: 300));
        await _room.localParticipant?.setScreenShareEnabled(true);
      } else {
        await _room.localParticipant?.setScreenShareEnabled(false);
        await _screenShareChannel.invokeMethod('stopScreenShareService').catchError((_) {});
      }

      // ignore: avoid_print
      print('[LiveClassRoom] Screen share toggled to $newState successfully');
      if (mounted) setState(() => _screenSharing = newState);
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[LiveClassRoom] Screen share toggle failed: $e');
      // ignore: avoid_print
      print(stackTrace);
      await _screenShareChannel.invokeMethod('stopScreenShareService').catchError((_) {});
      _showToast('Could not ${_screenSharing ? "stop" : "start"} screen sharing on this device.');
    } finally {
      _screenShareBusy = false;
    }
  }

  lk.VideoTrack? _screenShareTrackOf(lk.Participant participant) {
    for (final pub in participant.videoTrackPublications) {
      if (pub.source == lk.TrackSource.screenShareVideo) {
        final track = pub.track;
        if (track is lk.VideoTrack && !pub.muted) return track;
      }
    }
    return null;
  }

  /// Finds whoever is currently sharing their screen (local or remote) -
  /// screen share always takes over the main view when active.
  lk.Participant? _activeScreenSharer(List<lk.Participant> allParticipants) {
    for (final p in allParticipants) {
      if (_screenShareTrackOf(p) != null) return p;
    }
    return null;
  }

  // --- Whiteboard (LiveKit data channel - ephemeral, teacher draws only) ---

  Future<void> _openWhiteboard() async {
    setState(() => _whiteboardOpen = true);
    await _publish({'type': 'whiteboard_open', 'identity': _room.localParticipant?.identity ?? ''});
  }

  Future<void> _closeWhiteboard() async {
    setState(() => _whiteboardOpen = false);
    await _publish({'type': 'whiteboard_close', 'identity': _room.localParticipant?.identity ?? ''});
  }

  void _onWhiteboardPanStart(DragStartDetails details) {
    if (!widget.isTeacher) return;
    _currentStrokePoints = [details.localPosition];
    setState(() {});
  }

  void _onWhiteboardPanUpdate(DragUpdateDetails details) {
    if (!widget.isTeacher) return;
    setState(() => _currentStrokePoints = [..._currentStrokePoints, details.localPosition]);
  }

  Future<void> _onWhiteboardPanEnd(DragEndDetails details) async {
    if (!widget.isTeacher || _currentStrokePoints.isEmpty) return;
    final stroke = _Stroke(id: _newMsgId(), points: _currentStrokePoints, color: _whiteboardColor, width: _whiteboardStrokeWidth);
    setState(() {
      _whiteboardStrokes.add(stroke);
      _currentStrokePoints = [];
    });
    await _publish({
      'type': 'whiteboard_stroke',
      'id': stroke.id,
      'identity': _room.localParticipant?.identity ?? '',
      'points': stroke.points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'color': stroke.color.value,
      'width': stroke.width,
    });
  }

  Future<void> _clearWhiteboard() async {
    setState(() => _whiteboardStrokes.clear());
    await _publish({'type': 'whiteboard_clear', 'identity': _room.localParticipant?.identity ?? ''});
  }

  Future<void> _undoWhiteboard() async {
    setState(() {
      if (_whiteboardStrokes.isNotEmpty) _whiteboardStrokes.removeLast();
    });
    await _publish({'type': 'whiteboard_undo', 'identity': _room.localParticipant?.identity ?? ''});
  }

  void _openPanel(_SidePanel panel) {
    setState(() {
      _sidePanel = _sidePanel == panel ? _SidePanel.none : panel;
      if (_sidePanel == _SidePanel.chat) _unreadChatCount = 0;
    });
    if (panel == _SidePanel.attachments && _attachments.isEmpty && _resources.isEmpty && !_loadingAttachments) {
      _loadAttachments();
    }
  }

  Future<void> _loadAttachments() async {
    setState(() {
      _loadingAttachments = true;
      _attachmentsError = null;
    });
    try {
      final futures = <Future>[
        _classService.fetchResources(widget.classId),
        if (widget.subjectId != null) _assignmentService.fetchForSubject(widget.subjectId!) else Future.value(<AssignmentModel>[]),
      ];
      final results = await Future.wait(futures);
      _resources = results[0] as List<ClassResourceModel>;
      _attachments = results[1] as List<AssignmentModel>;
    } catch (e) {
      _attachmentsError = 'Could not load class resources.';
    }
    if (mounted) setState(() => _loadingAttachments = false);
  }

  Future<void> _uploadResource() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'ppt', 'pptx', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png', 'mp4', 'mov'],
    );
    if (result == null || result.files.single.path == null) return;

    final file = result.files.single;
    if (file.size > 25 * 1024 * 1024) {
      _showToast('File is too large (max 25MB).');
      return;
    }

    setState(() {
      _uploadingResource = true;
      _uploadProgress = 0;
    });
    try {
      final resource = await _classService.uploadResource(
        widget.classId,
        file.path!,
        file.name,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (mounted) setState(() => _resources = [resource, ..._resources]);
      await _publish({'type': 'resource_shared', 'identity': _room.localParticipant?.identity ?? '', 'name': resource.fileName});
      _showToast('Shared "${resource.fileName}" with the class');
    } catch (e) {
      _showToast('Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() {
        _uploadingResource = false;
        _uploadProgress = 0;
      });
    }
  }

  Future<void> _deleteResource(ClassResourceModel resource) async {
    try {
      await _classService.deleteResource(widget.classId, resource.id);
      if (mounted) setState(() => _resources.removeWhere((r) => r.id == resource.id));
    } catch (e) {
      _showToast('Failed to delete file.');
    }
  }

  Future<void> _openResource(ClassResourceModel resource) async {
    switch (resource.fileType) {
      case 'pdf':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ResourcePdfViewerScreen(url: resource.fileUrl, fileName: resource.fileName)));
        break;
      case 'image':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ResourceImageViewerScreen(url: resource.fileUrl, fileName: resource.fileName)));
        break;
      case 'video':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ResourceVideoViewerScreen(url: resource.fileUrl, fileName: resource.fileName)));
        break;
      default:
        // PPT/DOC/XLS - no in-app renderer available in Flutter without a
        // heavy/server-side conversion pipeline, so these download/open
        // via the system's own viewer instead of a broken in-app preview.
        final uri = Uri.tryParse(resource.fileUrl);
        if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          _showToast('Could not open this file.');
        }
    }
  }

  // --- Teacher moderation (existing admin API - unchanged) ---

  Future<void> _muteParticipant(String identity) async {
    try {
      await _classService.muteParticipant(widget.classId, identity);
      _showToast('Participant muted');
    } catch (e) {
      _showToast('Failed to mute participant');
    }
  }

  Future<void> _removeParticipant(String identity, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove participant?'),
        content: Text('$name will be disconnected from the class.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _classService.removeParticipant(widget.classId, identity);
    } catch (e) {
      _showToast('Failed to remove participant');
    }
  }

  Future<void> _muteAll() async {
    try {
      await _classService.muteAll(widget.classId);
      _showToast('All participants muted');
    } catch (e) {
      _showToast('Failed to mute all');
    }
  }

  Future<void> _toggleLockRoom() async {
    try {
      if (!_roomLocked) {
        await _classService.lockRoom(widget.classId);
      } else {
        await _classService.unlockRoom(widget.classId);
      }
      if (mounted) setState(() => _roomLocked = !_roomLocked);
    } catch (e) {
      _showToast('Failed to update room lock');
    }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 8),
              _moreMenuTile(Icons.people_alt_rounded, 'Participants', () {
                Navigator.pop(context);
                _openPanel(_SidePanel.participants);
              }, badge: (_room.remoteParticipants.length + 1)),
              _moreMenuTile(Icons.chat_bubble_rounded, 'Chat', () {
                Navigator.pop(context);
                _openPanel(_SidePanel.chat);
              }, badge: _unreadChatCount),
              _moreMenuTile(_localHandRaised ? Icons.back_hand_rounded : Icons.back_hand_outlined, _localHandRaised ? 'Lower Hand' : 'Raise Hand', () {
                Navigator.pop(context);
                _toggleRaiseHand();
              }, highlighted: _localHandRaised),
              if (widget.isTeacher)
                _moreMenuTile(
                  _teacherPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  _teacherPinned ? 'Unpin Myself' : 'Pin Myself as Main View',
                  () {
                    Navigator.pop(context);
                    _toggleTeacherPin();
                  },
                  subtitle: _teacherPinned ? 'Students can be tapped to highlight' : 'You are always the main view',
                  highlighted: _teacherPinned,
                ),
              if (widget.isTeacher && _spotlightIdentity != null)
                _moreMenuTile(Icons.highlight_off_rounded, 'Remove Spotlight', () {
                  Navigator.pop(context);
                  _setSpotlight(null);
                }, highlighted: true),
              if (widget.isTeacher)
                _moreMenuTile(Icons.front_hand_rounded, 'Raised Hands Queue', () {
                  Navigator.pop(context);
                  _openPanel(_SidePanel.raiseQueue);
                }, badge: _raisedHandsAt.length),
              _moreMenuTile(Icons.info_outline_rounded, 'Class Information', () {
                Navigator.pop(context);
                _openPanel(_SidePanel.classInfo);
              }),
              _moreMenuTile(Icons.attach_file_rounded, 'Attachments', () {
                Navigator.pop(context);
                _openPanel(_SidePanel.attachments);
              }),
              if (widget.isTeacher)
                _moreMenuTile(
                  _screenSharing ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
                  _screenSharing ? 'Stop Screen Share' : 'Share Screen',
                  () {
                    Navigator.pop(context);
                    _toggleScreenShare();
                  },
                  highlighted: _screenSharing,
                ),
              if (widget.isTeacher)
                _moreMenuTile(
                  _whiteboardOpen ? Icons.close_fullscreen_rounded : Icons.draw_rounded,
                  _whiteboardOpen ? 'Close Whiteboard' : 'Open Whiteboard',
                  () {
                    Navigator.pop(context);
                    if (_whiteboardOpen) {
                      _closeWhiteboard();
                    } else {
                      _openWhiteboard();
                    }
                  },
                  highlighted: _whiteboardOpen,
                ),
              _moreMenuTile(Icons.cameraswitch_rounded, 'Switch Camera', _cameraEnabled ? () {
                Navigator.pop(context);
                _switchCamera();
              } : null),
              _moreMenuTile(_speakerphoneOn ? Icons.volume_up_rounded : Icons.hearing_rounded, _speakerphoneOn ? 'Speaker' : 'Earpiece', () {
                Navigator.pop(context);
                _toggleSpeakerphone();
              }),
              _moreMenuTile(_speakerView ? Icons.grid_view_rounded : Icons.view_agenda_rounded, _speakerView ? 'Grid View' : 'Speaker View', () {
                Navigator.pop(context);
                _toggleViewMode();
              }),
              if (widget.isTeacher) ...[
                const Divider(color: Colors.white12, height: 20),
                _moreMenuTile(Icons.mic_off_rounded, 'Mute All', () {
                  Navigator.pop(context);
                  _muteAll();
                }),
                _moreMenuTile(
                  _roomLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                  _roomLocked ? 'Unlock Room' : 'Lock Room',
                  () {
                    Navigator.pop(context);
                    _toggleLockRoom();
                  },
                  subtitle: _roomLocked ? 'Allow new students to join' : 'Stop new students from joining',
                  highlighted: _roomLocked,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreMenuTile(IconData icon, String title, VoidCallback? onTap, {String? subtitle, int badge = 0, bool highlighted = false}) {
    return ListTile(
      enabled: onTap != null,
      leading: Icon(icon, color: highlighted ? AppColors.orange : (onTap != null ? Colors.white70 : Colors.white24)),
      title: Text(title, style: TextStyle(color: onTap != null ? Colors.white : Colors.white24, fontSize: 14)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)) : null,
      trailing: badge > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            )
          : null,
      onTap: onTap,
    );
  }

  void _toggleViewMode() => setState(() => _speakerView = !_speakerView);

  Future<void> _toggleSpeakerphone() async {
    final newState = !_speakerphoneOn;
    try {
      await lk.Hardware.instance.setSpeakerphoneOn(newState);
      if (mounted) setState(() => _speakerphoneOn = newState);
    } catch (e) {
      _showToast('Could not change audio output on this device.');
    }
  }

  Future<void> _toggleMic() async {
    final newState = !_micEnabled;
    await _room.localParticipant?.setMicrophoneEnabled(newState);
    if (mounted) setState(() => _micEnabled = newState);
  }

  Future<void> _toggleCamera() async {
    final newState = !_cameraEnabled;
    await _room.localParticipant?.setCameraEnabled(newState);
    if (mounted) setState(() => _cameraEnabled = newState);
  }

  Future<void> _switchCamera() async {
    if (!_cameraEnabled || _switchingCamera) return;
    setState(() => _switchingCamera = true);
    try {
      final newPosition = _cameraPosition == lk.CameraPosition.front ? lk.CameraPosition.back : lk.CameraPosition.front;
      final pubs = _room.localParticipant?.videoTrackPublications ?? [];
      for (final pub in pubs) {
        final track = pub.track;
        if (track is lk.LocalVideoTrack) {
          await track.setCameraPosition(newPosition);
          _cameraPosition = newPosition;
        }
      }
    } catch (e) {
      _showToast('Could not switch camera on this device.');
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.isTeacher ? 'End class for everyone?' : 'Leave class?'),
        content: Text(widget.isTeacher ? 'This will disconnect all students.' : 'You can rejoin while the class is still live.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.isTeacher ? 'End Class' : 'Leave', style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _room.disconnect();
    if (widget.isTeacher && widget.onEndClass != null) {
      await widget.onEndClass!();
    }
    // BUG FIX (critical): do NOT pop here. _room.disconnect() above
    // already fires RoomDisconnectedEvent, whose listener (see
    // ..on<lk.RoomDisconnectedEvent> in initState) does
    // popUntil((route) => route.isFirst) - that's what correctly
    // returns the student/teacher to the Live Classes list for every
    // disconnect reason (manual leave, teacher ending the class, or the
    // connection simply dropping). Calling Navigator.pop() again here
    // tore an extra route off the stack on top of that popUntil,
    // landing the user on a blank/root screen instead.
  }

  @override
  void dispose() {
    if (_screenSharing) {
      _screenShareChannel.invokeMethod('stopScreenShareService').catchError((_) {});
    }
    _fallbackRebuildTimer?.cancel();
    _endingSoonTimer?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatSearchController.dispose();
    _listener?.dispose();
    _room.dispose();
    super.dispose();
  }

  lk.VideoTrack? _videoTrackOf(lk.Participant participant) {
    for (final pub in participant.videoTrackPublications) {
      final track = pub.track;
      if (track is lk.VideoTrack && !pub.muted) return track;
    }
    return null;
  }

  bool _isMicOn(lk.Participant participant) {
    for (final pub in participant.audioTrackPublications) {
      if (!pub.muted) return true;
    }
    return false;
  }

  /// Resolves who gets the large video, in priority order:
  /// Spotlight (teacher's explicit choice) > Teacher Pin (default mode,
  /// teacher always primary) > manual tap-to-highlight > auto (active
  /// speaker, then just the first participant).
  lk.RemoteParticipant? _primaryParticipant(List<lk.RemoteParticipant> remoteParticipants) {
    if (remoteParticipants.isEmpty) return null;

    if (_spotlightIdentity != null) {
      final spotlighted = remoteParticipants.where((p) => p.identity == _spotlightIdentity).toList();
      if (spotlighted.isNotEmpty) return spotlighted.first;
    }

    final teacher = remoteParticipants.where((p) => p.identity.startsWith('teacher-')).toList();
    if (_teacherPinned && teacher.isNotEmpty) return teacher.first;

    if (_manualPrimaryIdentity != null) {
      final manual = remoteParticipants.where((p) => p.identity == _manualPrimaryIdentity).toList();
      if (manual.isNotEmpty) return manual.first;
    }

    if (teacher.isNotEmpty) return teacher.first;
    final speaking = remoteParticipants.where((p) => _activeSpeakerIdentities.contains(p.identity)).toList();
    if (speaking.isNotEmpty) return speaking.first;
    return remoteParticipants.first;
  }

  /// Tap-to-highlight a thumbnail. Per the classroom brief, this does
  /// nothing while the teacher is pinned or spotlighting someone - the
  /// student just gets a brief explanation instead of a silent no-op.
  void _onTileTap(lk.RemoteParticipant tapped) {
    if (_spotlightIdentity != null) {
      _showToast('The teacher is spotlighting a participant right now.');
      return;
    }
    if (_teacherPinned) {
      _showToast('The teacher has pinned themselves as the main view.');
      return;
    }
    setState(() => _manualPrimaryIdentity = _manualPrimaryIdentity == tapped.identity ? null : tapped.identity);
  }

  Future<void> _toggleTeacherPin() async {
    setState(() {
      _teacherPinned = !_teacherPinned;
      if (_teacherPinned) _manualPrimaryIdentity = null;
    });
  }

  void _setSpotlight(String? identity) {
    setState(() => _spotlightIdentity = identity);
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String _fmtTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_connecting || _error != null) {
          if (mounted) Navigator.of(context).pop();
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave this class?'),
            content: const Text('You will be disconnected from the live session.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
        }
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_connecting) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
              ],
            ),
          ),
        ),
      );
    }

    final remoteParticipants = _room.remoteParticipants.values.toList();
    final localParticipant = _room.localParticipant;
    final List<lk.Participant> allParticipants = [if (localParticipant != null) localParticipant, ...remoteParticipants];
    final primary = _primaryParticipant(remoteParticipants);
    final others = remoteParticipants.where((p) => p.identity != primary?.identity).toList();
    final screenSharer = _activeScreenSharer(allParticipants);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              bottom: 84,
              child: _whiteboardOpen
                  ? _buildWhiteboardView(remoteParticipants)
                  : (screenSharer != null
                      ? _buildScreenShareView(screenSharer, allParticipants.where((p) => p.identity != screenSharer.identity).toList())
                      : (remoteParticipants.isEmpty
                          ? _buildWaitingState()
                          : (_speakerView
                              ? _buildFocusedLayout(primary, others)
                              : GridView.count(
                                  crossAxisCount: remoteParticipants.length > 1 ? 2 : 1,
                                  padding: const EdgeInsets.all(8),
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  children: remoteParticipants.map((p) => _participantTile(p)).toList(),
                                )))),
            ),

            Positioned(
              top: 4,
              left: 12,
              right: 12,
              child: _screenSharing
                  ? Material(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(24),
                      elevation: 4,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _toggleScreenShare,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.screen_share_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text('You are presenting your screen', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                              Icon(Icons.stop_circle_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text('Stop Sharing', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                            child: Text(widget.classTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                    ),
            ),

            // --- Pinned announcements ---
            if (_announcements.isNotEmpty)
              Positioned(
                top: 44,
                left: 12,
                right: 12,
                child: Column(
                  children: _announcements.map((a) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.92), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.campaign_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text('${a.teacherName} \u2022 ${_fmtTime(a.time)}', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              ],
                            ),
                          ),
                          if (widget.isTeacher)
                            InkWell(onTap: () => _removeAnnouncement(a), child: const Icon(Icons.close_rounded, color: Colors.white, size: 16)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            if (localParticipant != null) _buildDraggablePip(localParticipant),

            Positioned(left: 0, right: 0, bottom: 0, child: _buildToolbar()),

            _buildSlideUpPanel(allParticipants),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1.0),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.purple,
                child: Text(
                  widget.classTitle.isNotEmpty ? widget.classTitle[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.classTitle, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            if (widget.subjectName.isNotEmpty || widget.lessonTitle.isNotEmpty)
              Text(
                [widget.subjectName, widget.lessonTitle].where((s) => s.isNotEmpty).join(' \u2022 '),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 20),
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
            const SizedBox(height: 14),
            const Text('Waiting for participants to join', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusedLayout(lk.RemoteParticipant? primary, List<lk.RemoteParticipant> others) {
    return Column(
      children: [
        // ~68% of the available video area for the primary tile, per the
        // "teacher always the focus" classroom layout.
        Expanded(
          flex: 68,
          child: primary != null ? _participantTile(primary, isPrimary: true) : const SizedBox.shrink(),
        ),
        if (others.isNotEmpty)
          Expanded(
            flex: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final p = others[index];
                return SizedBox(width: 84, child: _participantTile(p, onTap: () => _onTileTap(p)));
              },
            ),
          ),
      ],
    );
  }

  Widget _buildScreenShareView(lk.Participant sharer, List<lk.Participant> others) {
    final track = _screenShareTrackOf(sharer);
    final isMe = sharer.identity == (_room.localParticipant?.identity ?? '');
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: Colors.black,
            // Fix: never render the local user's OWN screen-share track
            // back to themselves. With "Entire Screen" capture, doing so
            // recaptures the app showing that same video, creating an
            // infinite recursive mirror. Other participants still see
            // the real VideoTrackRenderer normally - only the sharer's
            // own view is replaced with a static placeholder.
            child: isMe
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.screen_share_rounded, color: Colors.white54, size: 48),
                        SizedBox(height: 12),
                        Text('You are presenting your screen', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('Other participants can see your shared screen', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  )
                : (track != null ? lk.VideoTrackRenderer(track) : const Center(child: CircularProgressIndicator(color: Colors.white54))),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
            child: Text(
              isMe ? 'You are sharing your screen' : '${sharer.name.isNotEmpty ? sharer.name : sharer.identity} is sharing their screen',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
        // Presenter's own camera as a small PiP over the shared screen.
        Positioned(
          top: 44,
          right: 12,
          child: SizedBox(width: 84, height: 112, child: _participantTile(sharer)),
        ),
        if (others.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: others.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SizedBox(width: 76, child: _participantTile(others[index])),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWhiteboardView(List<lk.RemoteParticipant> remoteParticipants) {
    const colors = [Colors.red, Colors.blue, Colors.green, Colors.black, Colors.orange];
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: _onWhiteboardPanStart,
              onPanUpdate: _onWhiteboardPanUpdate,
              onPanEnd: _onWhiteboardPanEnd,
              child: CustomPaint(
                painter: _WhiteboardPainter(strokes: _whiteboardStrokes, currentPoints: _currentStrokePoints, currentColor: _whiteboardColor, currentWidth: _whiteboardStrokeWidth),
                size: Size.infinite,
              ),
            ),
          ),
          Container(
            color: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (widget.isTeacher) ...[
                  ...colors.map((c) => GestureDetector(
                        onTap: () => setState(() => _whiteboardColor = c),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: _whiteboardColor == c ? Border.all(color: Colors.black, width: 2) : null),
                        ),
                      )),
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(Icons.undo_rounded, size: 20), onPressed: _undoWhiteboard),
                  IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20), onPressed: _clearWhiteboard),
                ] else
                  const Expanded(child: Text('Teacher\u2019s Whiteboard', style: TextStyle(fontSize: 12, color: Colors.black54))),
                const Spacer(),
                if (widget.isTeacher)
                  TextButton.icon(onPressed: _closeWhiteboard, icon: const Icon(Icons.close_rounded, size: 18), label: const Text('Close')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggablePip(lk.LocalParticipant localParticipant) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 80),
      left: _pipOffset.dx,
      top: _pipOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final size = MediaQuery.of(context).size;
            final newX = (_pipOffset.dx + details.delta.dx).clamp(0.0, size.width - 96);
            final newY = (_pipOffset.dy + details.delta.dy).clamp(0.0, size.height - 220);
            _pipOffset = Offset(newX, newY);
          });
        },
        child: SizedBox(width: 96, height: 128, child: _participantTile(localParticipant, isLocal: true)),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _toolbarButton(_micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded, _micEnabled ? Colors.white24 : AppColors.error, _toggleMic),
          const SizedBox(width: 22),
          _toolbarButton(_cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded, _cameraEnabled ? Colors.white24 : AppColors.error, _toggleCamera),
          const SizedBox(width: 22),
          _toolbarButton(Icons.call_end_rounded, AppColors.error, _leave, large: true),
          const SizedBox(width: 22),
          _badgedToolbarButton(Icons.more_horiz_rounded, Colors.white24, _showMoreMenu, badgeCount: _unreadChatCount + (widget.isTeacher ? _raisedHandsAt.length : 0)),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, Color bg, VoidCallback onTap, {bool large = false}) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: EdgeInsets.all(large ? 16 : 14), child: Icon(icon, color: Colors.white, size: large ? 26 : 22)),
      ),
    );
  }

  Widget _badgedToolbarButton(IconData icon, Color bg, VoidCallback onTap, {int badgeCount = 0}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _toolbarButton(icon, bg, onTap),
        if (badgeCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text('$badgeCount', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  Widget _buildSlideUpPanel(List<lk.Participant> allParticipants) {
    final open = _sidePanel != _SidePanel.none;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: open ? 84 : -600,
      height: MediaQuery.of(context).size.height * 0.55,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 200) setState(() => _sidePanel = _SidePanel.none);
        },
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, -6))],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(_panelTitle(allParticipants.length), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    const Spacer(),
                    if (_sidePanel == _SidePanel.chat)
                      IconButton(icon: Icon(_chatSearchOpen ? Icons.close_rounded : Icons.search_rounded, color: Colors.white70, size: 20), onPressed: () => setState(() => _chatSearchOpen = !_chatSearchOpen)),
                    IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20), onPressed: () => setState(() => _sidePanel = _SidePanel.none)),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(child: _panelBody(allParticipants)),
            ],
          ),
        ),
      ),
    );
  }

  String _panelTitle(int participantCount) {
    switch (_sidePanel) {
      case _SidePanel.chat:
        return 'Chat';
      case _SidePanel.participants:
        return 'Participants ($participantCount)';
      case _SidePanel.raiseQueue:
        return 'Raised Hands (${_raisedHandsAt.length})';
      case _SidePanel.classInfo:
        return 'Class Information';
      case _SidePanel.attachments:
        return 'Attachments';
      case _SidePanel.none:
        return '';
    }
  }

  Widget _panelBody(List<lk.Participant> allParticipants) {
    switch (_sidePanel) {
      case _SidePanel.chat:
        return _buildChatPanel();
      case _SidePanel.participants:
        return _buildParticipantsPanel(allParticipants);
      case _SidePanel.raiseQueue:
        return _buildRaiseQueuePanel(allParticipants);
      case _SidePanel.classInfo:
        return _buildClassInfoPanel(allParticipants.length);
      case _SidePanel.attachments:
        return _buildAttachmentsPanel();
      case _SidePanel.none:
        return const SizedBox.shrink();
    }
  }

  Widget _buildChatPanel() {
    final query = _chatSearchController.text.trim().toLowerCase();
    final visible = query.isEmpty ? _chatMessages : _chatMessages.where((m) => m.text.toLowerCase().contains(query)).toList();

    return Column(
      children: [
        if (_chatSearchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: TextField(
              controller: _chatSearchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search messages...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                filled: true,
                fillColor: Colors.grey.shade800,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(query.isEmpty ? 'No messages yet.' : 'No messages match "$query".', style: const TextStyle(color: Colors.white38, fontSize: 12)))
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final m = visible[index];
                    final localIdentity = _room.localParticipant?.identity ?? '';
                    final isMe = m.identity == localIdentity;
                    final canDelete = widget.isTeacher || isMe;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: canDelete ? () => _deleteMessage(m) : null,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? AppColors.purple : (m.isTeacher ? AppColors.orange.withOpacity(0.85) : Colors.grey.shade800),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 16),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    children: [
                                      Text(m.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                      if (m.isTeacher) ...[
                                        const SizedBox(width: 4),
                                        const Text('\u2022 Teacher', style: TextStyle(color: Colors.white70, fontSize: 9, fontStyle: FontStyle.italic)),
                                      ],
                                    ],
                                  ),
                                ),
                              Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_fmtTime(m.time), style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9)),
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.done_rounded, size: 11, color: Colors.white.withOpacity(0.6)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    maxLength: 500,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      counterText: '',
                      filled: true,
                      fillColor: Colors.grey.shade800,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.purple,
                  shape: const CircleBorder(),
                  child: InkWell(customBorder: const CircleBorder(), onTap: _sendChat, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.send_rounded, color: Colors.white, size: 20))),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsPanel(List<lk.Participant> allParticipants) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: allParticipants.length,
      itemBuilder: (context, index) {
        final p = allParticipants[index];
        final isTeacherRole = p.identity.startsWith('teacher-');
        final isSelf = p.identity == (_room.localParticipant?.identity ?? '');
        final micOn = _isMicOn(p);
        final camOn = _videoTrackOf(p) != null;
        final handRaised = _raisedHandsAt.containsKey(p.identity);
        final quality = _connectionQuality[p.identity];
        final canModerate = widget.isTeacher && !isSelf;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.purple,
            child: Text((p.name.isNotEmpty ? p.name[0] : '?').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          title: Text('${p.name.isNotEmpty ? p.name : p.identity}${isSelf ? ' (You)' : ''}', style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text(isTeacherRole ? 'Teacher' : 'Student', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (handRaised) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.back_hand_rounded, color: AppColors.orange, size: 16)),
              Icon(_qualityIcon(quality), color: _qualityColor(quality), size: 16),
              const SizedBox(width: 6),
              Icon(micOn ? Icons.mic_rounded : Icons.mic_off_rounded, color: micOn ? Colors.white70 : AppColors.error, size: 16),
              const SizedBox(width: 6),
              Icon(camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded, color: camOn ? Colors.white70 : AppColors.error, size: 16),
              if (canModerate)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 18),
                  color: const Color(0xFF2C2C2E),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'spotlight',
                      child: Text(_spotlightIdentity == p.identity ? 'Remove Spotlight' : 'Spotlight', style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                    const PopupMenuItem(value: 'mute', child: Text('Mute', style: TextStyle(color: Colors.white, fontSize: 13))),
                    const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: AppColors.error, fontSize: 13))),
                  ],
                  onSelected: (value) {
                    if (value == 'spotlight') _setSpotlight(_spotlightIdentity == p.identity ? null : p.identity);
                    if (value == 'mute') _muteParticipant(p.identity);
                    if (value == 'remove') _removeParticipant(p.identity, p.name.isNotEmpty ? p.name : p.identity);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRaiseQueuePanel(List<lk.Participant> allParticipants) {
    final entries = _raisedHandsAt.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    if (entries.isEmpty) {
      return const Center(child: Text('No raised hands right now.', style: TextStyle(color: Colors.white38, fontSize: 12)));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: _clearAllHands, icon: const Icon(Icons.clear_all_rounded, size: 16, color: AppColors.error), label: const Text('Clear All', style: TextStyle(color: AppColors.error, fontSize: 12))),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final identity = entries[index].key;
              final time = entries[index].value;
              final participant = allParticipants.where((p) => p.identity == identity).firstOrNull;
              final name = participant?.name.isNotEmpty == true ? participant!.name : identity;
              return ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.orange, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: Text('Raised ${_timeAgo(time)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(onPressed: () => _acceptHand(identity), child: const Text('Accept', style: TextStyle(fontSize: 12))),
                    TextButton(onPressed: () => _lowerHand(identity), child: const Text('Lower', style: TextStyle(color: Colors.white54, fontSize: 12))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClassInfoPanel(int participantCount) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.description.isNotEmpty) ...[
          const Text('Description', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(widget.description, style: const TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 16),
        ],
        _infoRow(Icons.menu_book_outlined, 'Subject', widget.subjectName.isNotEmpty ? widget.subjectName : '\u2014'),
        _infoRow(Icons.play_lesson_outlined, 'Lesson', widget.lessonTitle.isNotEmpty ? widget.lessonTitle : '\u2014'),
        if (widget.scheduledStart != null) _infoRow(Icons.event_outlined, 'Start Time', _fmtTime(widget.scheduledStart!)),
        if (widget.scheduledStart != null && widget.scheduledEnd != null)
          _infoRow(Icons.timer_outlined, 'Duration', '${widget.scheduledEnd!.difference(widget.scheduledStart!).inMinutes} min'),
        _infoRow(Icons.live_tv_rounded, 'Meeting Status', 'Live'),
        _infoRow(Icons.people_outline_rounded, 'Participants', '$participantCount'),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white54, size: 16),
          const SizedBox(width: 10),
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildAttachmentsPanel() {
    return Column(
      children: [
        if (widget.isTeacher)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploadingResource ? null : _uploadResource,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
                icon: _uploadingResource
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file_rounded, color: Colors.white, size: 18),
                label: Text(_uploadingResource ? 'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%' : 'Upload File (PDF, PPT, Image, Doc, Video)', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
        Expanded(
          child: _loadingAttachments
              ? const Center(child: CircularProgressIndicator(color: Colors.white54))
              : (_attachmentsError != null
                  ? Center(child: Text(_attachmentsError!, style: const TextStyle(color: Colors.white54, fontSize: 12)))
                  : (_resources.isEmpty && _attachments.isEmpty
                      ? const Center(child: Text('Nothing shared yet.', style: TextStyle(color: Colors.white38, fontSize: 12)))
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            if (_resources.isNotEmpty) ...[
                              const Padding(padding: EdgeInsets.only(bottom: 6, left: 4), child: Text('Shared Files', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700))),
                              ..._resources.map((r) => _resourceCard(r)),
                              const SizedBox(height: 12),
                            ],
                            if (_attachments.isNotEmpty) ...[
                              const Padding(padding: EdgeInsets.only(bottom: 6, left: 4), child: Text('Assignments', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700))),
                              ..._attachments.map((a) => _assignmentCard(a)),
                            ],
                          ],
                        ))),
        ),
      ],
    );
  }

  IconData _resourceIcon(String fileType) {
    switch (fileType) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'ppt':
        return Icons.slideshow_rounded;
      case 'doc':
        return Icons.description_rounded;
      case 'xls':
        return Icons.grid_on_rounded;
      case 'image':
        return Icons.image_rounded;
      case 'video':
        return Icons.videocam_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _resourceCard(ClassResourceModel r) {
    final canDelete = widget.isTeacher;
    return Card(
      color: Colors.grey.shade900,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_resourceIcon(r.fileType), color: AppColors.purple),
        title: Text(r.fileName, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
        subtitle: Text('${_formatFileSize(r.fileSizeBytes)} \u2022 Shared by teacher', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        trailing: canDelete
            ? IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18), onPressed: () => _deleteResource(r))
            : const Icon(Icons.open_in_new_rounded, color: Colors.white38, size: 16),
        onTap: () => _openResource(r),
      ),
    );
  }

  Widget _assignmentCard(AssignmentModel a) {
    return Card(
      color: Colors.grey.shade900,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.assignment_rounded, color: AppColors.purple),
        title: Text(a.title, style: const TextStyle(color: Colors.white, fontSize: 13)),
        subtitle: Text('${a.maxMarks} marks \u2022 ${a.difficulty}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: () {
          // Pushes on top of this screen - the LiveKit Room object stays
          // connected in the background since this State isn't disposed,
          // so returning here keeps the call live.
          Navigator.push(context, MaterialPageRoute(builder: (_) => AssignmentDetailScreen(assignmentId: a.id)));
        },
      ),
    );
  }

  IconData _qualityIcon(lk.ConnectionQuality? q) {
    switch (q) {
      case lk.ConnectionQuality.excellent:
        return Icons.signal_cellular_alt_rounded;
      case lk.ConnectionQuality.good:
        return Icons.signal_cellular_alt_2_bar_rounded;
      case lk.ConnectionQuality.poor:
        return Icons.signal_cellular_alt_1_bar_rounded;
      default:
        return Icons.signal_cellular_connected_no_internet_0_bar_rounded;
    }
  }

  Color _qualityColor(lk.ConnectionQuality? q) {
    switch (q) {
      case lk.ConnectionQuality.excellent:
        return AppColors.green;
      case lk.ConnectionQuality.good:
        return AppColors.orange;
      case lk.ConnectionQuality.poor:
        return AppColors.error;
      default:
        return Colors.white38;
    }
  }

  Widget _participantTile(lk.Participant participant, {bool isLocal = false, bool isPrimary = false, VoidCallback? onTap}) {
    final videoTrack = _videoTrackOf(participant);
    final displayName = participant.name.isNotEmpty ? participant.name : participant.identity;
    final isTeacherRole = participant.identity.startsWith('teacher-');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final isSpeaking = _activeSpeakerIdentities.contains(participant.identity);
    final isSpotlighted = _spotlightIdentity == participant.identity;
    final handRaised = _raisedHandsAt.containsKey(participant.identity);
    final quality = _connectionQuality[participant.identity];

    final tile = Container(
      key: ValueKey('${participant.identity}-${videoTrack != null}'),
      margin: isLocal ? EdgeInsets.zero : const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(isLocal ? 14 : (isPrimary ? 20 : 16)),
        border: isSpotlighted
            ? Border.all(color: AppColors.orange, width: 3)
            : (isSpeaking ? Border.all(color: AppColors.blue, width: 3) : Border.all(color: Colors.white10, width: 1)),
        boxShadow: isSpeaking
            ? [BoxShadow(color: AppColors.blue.withOpacity(0.5), blurRadius: 12, spreadRadius: 1)]
            : [const BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack != null)
            lk.VideoTrackRenderer(videoTrack)
          else
            Container(
              color: Colors.grey.shade800,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: isLocal ? 18 : 28,
                      backgroundColor: AppColors.purple,
                      child: Text(initial, style: TextStyle(color: Colors.white, fontSize: isLocal ? 14 : 22, fontWeight: FontWeight.w700)),
                    ),
                    if (!isLocal) ...[
                      const SizedBox(height: 8),
                      Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(isTeacherRole ? 'Teacher' : 'Student', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                    ],
                  ],
                ),
              ),
            ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: Text(isLocal ? 'You' : displayName, style: const TextStyle(color: Colors.white, fontSize: 10), overflow: TextOverflow.ellipsis),
            ),
          ),
          if (!isLocal)
            Positioned(right: 6, top: 6, child: Icon(_qualityIcon(quality), color: _qualityColor(quality), size: 16)),
          if (handRaised)
            Positioned(
              right: 6,
              top: isLocal ? 6 : 26,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                child: const Icon(Icons.back_hand_rounded, color: Colors.white, size: 12),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}

/// Renders all committed whiteboard strokes plus the one currently being
/// drawn (if any) - repaints only when strokes actually change.
class _WhiteboardPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentWidth;

  _WhiteboardPainter({required this.strokes, required this.currentPoints, required this.currentColor, required this.currentWidth});

  void _paintStroke(Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke.points, stroke.color, stroke.width);
    }
    _paintStroke(canvas, currentPoints, currentColor, currentWidth);
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) {
    return oldDelegate.strokes.length != strokes.length || oldDelegate.currentPoints.length != currentPoints.length;
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/liveclass/live_class_room_screen.dart"), $content_lib_screens_liveclass_live_class_room_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/liveclass/live_class_room_screen.dart" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Yellow
Write-Host "  1. flutter analyze   (to sanity check - I could not run Dart tooling myself)"
Write-Host "  2. flutter run (or rebuild your APK) and test: AI Quiz Generator -> submit -> Live Class -> Leave"