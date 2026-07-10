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

  Map<String, dynamic> toAnsweredJson() => {
        'question_type': questionType,
        'question': question,
        'options': options,
        if (correctOption != null) 'correct_option': correctOption,
        if (correctOptions != null) 'correct_options': correctOptions,
        if (correctText != null) 'correct_text': correctText,
        if (hint != null) 'hint': hint,
        if (explanation != null) 'explanation': explanation,
        'difficulty_score': difficultyScore,
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
