import '../core/utils/safe_parse.dart';

/// Mirrors the backend's progress.SubjectProgress: how many of a subject's
/// lessons the current user has completed, and which specific lesson IDs
/// (used to set LessonModel.isCompleted without a call per lesson).
class SubjectProgressModel {
  final int subjectId;
  final int totalLessons;
  final int completedLessons;
  final double percentage; // 0.0 - 1.0
  final List<int> completedLessonIds;

  SubjectProgressModel({
    required this.subjectId,
    required this.totalLessons,
    required this.completedLessons,
    required this.percentage,
    required this.completedLessonIds,
  });

  factory SubjectProgressModel.fromJson(Map<String, dynamic> json) {
    return SubjectProgressModel(
      subjectId: json['subject_id'] as int? ?? 0,
      totalLessons: json['total_lessons'] as int? ?? 0,
      completedLessons: json['completed_lessons'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      completedLessonIds: (json['completed_lesson_ids'] as List<dynamic>? ?? [])
          .map((e) => safeInt(e))
          .whereType<int>()
          .toList(),
    );
  }
}
