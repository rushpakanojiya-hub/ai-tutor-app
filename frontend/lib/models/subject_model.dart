/// Plain data model for a subject within a category (e.g. "Mathematics").
///
/// Difficulty is an editorial tag (Beginner/Intermediate/Advanced) set by
/// the backend. There's deliberately no `rating` or `mockTestCount` field:
/// neither has a real system behind it yet, so neither is faked here.
class SubjectModel {
  final int id;
  final int categoryId;
  final String name;
  final String description;
  final String thumbnail;
  final String difficulty;
  final int lessonCount;
  final int completedLessons;
  final int notesCount;
  final int quizCount;
  final double learningHours;
  final double completedHours;
  final double progressPercentage;

  SubjectModel({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.thumbnail,
    required this.difficulty,
    required this.lessonCount,
    required this.completedLessons,
    required this.notesCount,
    required this.quizCount,
    required this.learningHours,
    required this.completedHours,
    required this.progressPercentage,
  });

  factory SubjectModel.fromJson(Map<String, dynamic> json) {
    return SubjectModel(
      id: json['id'] as int? ?? 0,
      categoryId: json['category_id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? 'Intermediate',
      lessonCount: json['lesson_count'] as int? ?? 0,
      completedLessons: json['completed_lessons'] as int? ?? 0,
      notesCount: json['notes_count'] as int? ?? 0,
      quizCount: json['quiz_count'] as int? ?? 0,
      learningHours: (json['learning_hours'] as num?)?.toDouble() ?? 0.0,
      completedHours: (json['completed_hours'] as num?)?.toDouble() ?? 0.0,
      progressPercentage: (json['progress_percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
