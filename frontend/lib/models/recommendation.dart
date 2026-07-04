/// A "what to learn next" suggestion â€” mirrors the backend's
/// recommendations table row, joined with the recommended lesson's title
/// and subject for direct display.
class RecommendationModel {
  final int id;
  final int lessonId;
  final int recommendedLessonId;
  final String recommendedTitle;
  final int recommendedSubjectId;
  final String subjectName;

  RecommendationModel({
    required this.id,
    required this.lessonId,
    required this.recommendedLessonId,
    required this.recommendedTitle,
    required this.recommendedSubjectId,
    required this.subjectName,
  });

  factory RecommendationModel.fromJson(Map<String, dynamic> json) {
    return RecommendationModel(
      id: json['id'] as int? ?? 0,
      lessonId: json['lesson_id'] as int? ?? 0,
      recommendedLessonId: json['recommended_lesson_id'] as int? ?? 0,
      recommendedTitle: json['recommended_title'] as String? ?? '',
      recommendedSubjectId: json['recommended_subject_id'] as int? ?? 0,
      subjectName: json['subject_name'] as String? ?? '',
    );
  }
}
