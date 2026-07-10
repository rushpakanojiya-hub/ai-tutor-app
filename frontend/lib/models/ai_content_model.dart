/// A single multiple-choice quiz question.
class QuizQuestionModel {
  final String question;
  final List<String> options;
  final int correctOption;

  QuizQuestionModel({required this.question, required this.options, required this.correctOption});

  factory QuizQuestionModel.fromJson(Map<String, dynamic> json) {
    return QuizQuestionModel(
      question: json['question'] as String? ?? '',
      options: (json['options'] as List<dynamic>? ?? []).map((e) => e as String? ?? '').toList(),
      correctOption: json['correct_option'] as int? ?? 0,
    );
  }
}

/// AI-generated educational content for a lesson: explanation, summary,
/// key points, worked examples, practice questions, and a quiz.
class AiContentModel {
  final int lessonId;
  final String explanation;
  final String summary;
  final List<String> keyPoints;
  final List<String> examples;
  final List<String> practiceQuestions;
  final List<QuizQuestionModel> quiz;

  AiContentModel({
    required this.lessonId,
    required this.explanation,
    required this.summary,
    required this.keyPoints,
    required this.examples,
    required this.practiceQuestions,
    required this.quiz,
  });

  factory AiContentModel.fromJson(Map<String, dynamic> json) {
    return AiContentModel(
      lessonId: json['lesson_id'] as int? ?? 0,
      explanation: json['explanation'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      keyPoints: (json['key_points'] as List<dynamic>? ?? []).map((e) => e as String? ?? '').toList(),
      examples: (json['examples'] as List<dynamic>? ?? []).map((e) => e as String? ?? '').toList(),
      practiceQuestions: (json['practice_questions'] as List<dynamic>? ?? []).map((e) => e as String? ?? '').toList(),
      quiz: (json['quiz'] as List<dynamic>? ?? [])
          .map((e) => QuizQuestionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
