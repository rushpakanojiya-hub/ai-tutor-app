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
  final String videoSource; // 'upload' | 'youtube'
  final String pdfUrl;
  final String pdfTitle;
  final String pdfDescription;
  final String assignmentUrl;
  final int duration;
  final int orderNumber;
  final String status; // 'draft' | 'published'

  AdminLessonModel({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.videoSource,
    required this.pdfUrl,
    required this.pdfTitle,
    required this.pdfDescription,
    required this.assignmentUrl,
    required this.duration,
    required this.orderNumber,
    required this.status,
  });

  factory AdminLessonModel.fromJson(Map<String, dynamic> json) {
    return AdminLessonModel(
      id: json['id'] as int? ?? 0,
      subjectId: json['subject_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      videoSource: json['video_source'] as String? ?? 'upload',
      pdfUrl: json['pdf_url'] as String? ?? '',
      pdfTitle: json['pdf_title'] as String? ?? '',
      pdfDescription: json['pdf_description'] as String? ?? '',
      assignmentUrl: json['assignment_url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      orderNumber: json['order_number'] as int? ?? 0,
      status: json['status'] as String? ?? 'draft',
    );
  }

  // Lesson Resource Management (Video/PDF/publish) helper getters.
  String get youtubeUrl => videoSource == 'youtube' ? videoUrl : '';
  bool get hasVideo => videoUrl.isNotEmpty;
  bool get hasPdf => pdfUrl.isNotEmpty;
  bool get isPublished => status == 'published';
}