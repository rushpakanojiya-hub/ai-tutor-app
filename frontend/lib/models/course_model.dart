class AdminCourseModel {
  final int id;
  final String name;
  final String description;
  final String thumbnail;
  final String difficulty;
  final String status; // draft | published
  final int categoryId;
  final String categoryName;
  final int totalLessons;
  final int enrolledCount;

  AdminCourseModel({
    required this.id,
    required this.name,
    required this.description,
    required this.thumbnail,
    required this.difficulty,
    required this.status,
    required this.categoryId,
    required this.categoryName,
    required this.totalLessons,
    required this.enrolledCount,
  });

  factory AdminCourseModel.fromJson(Map<String, dynamic> json) {
    return AdminCourseModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? 'Intermediate',
      status: json['status'] as String? ?? 'draft',
      categoryId: json['category_id'] as int? ?? 0,
      categoryName: json['category_name'] as String? ?? '',
      totalLessons: json['total_lessons'] as int? ?? 0,
      enrolledCount: json['enrolled_count'] as int? ?? 0,
    );
  }
}

class AdminLessonModel {
  final int id;
  final int subjectId;
  final String title;
  final String description;
  final String videoUrl;
  final String pdfUrl;
  final String assignmentUrl;
  final int duration;
  final int orderNumber;

  AdminLessonModel({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.pdfUrl,
    required this.assignmentUrl,
    required this.duration,
    required this.orderNumber,
  });

  factory AdminLessonModel.fromJson(Map<String, dynamic> json) {
    return AdminLessonModel(
      id: json['id'] as int? ?? 0,
      subjectId: json['subject_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      pdfUrl: json['pdf_url'] as String? ?? '',
      assignmentUrl: json['assignment_url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      orderNumber: json['order_number'] as int? ?? 0,
    );
  }
}
