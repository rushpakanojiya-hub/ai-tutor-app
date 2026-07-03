/// Plain data model for a subject within a category (e.g. "Mathematics").
class SubjectModel {
  final int id;
  final int categoryId;
  final String name;
  final String description;
  final String thumbnail;
  final int lessonCount;

  SubjectModel({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.thumbnail,
    required this.lessonCount,
  });

  factory SubjectModel.fromJson(Map<String, dynamic> json) {
    return SubjectModel(
      id: json['id'] as int,
      categoryId: json['category_id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
      lessonCount: json['lesson_count'] as int? ?? 0,
    );
  }
}
