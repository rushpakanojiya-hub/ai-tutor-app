/// Plain data model for a single lesson (video + optional PDF content).
class LessonModel {
  final int id;
  final int subjectId;
  final String title;
  final String description;
  final String videoUrl;
  final String pdfUrl;
  final int duration; // minutes
  final int orderNumber;

  /// Not part of the API response â€” set locally by the UI once a lesson
  /// has been watched, so LessonsScreen can show a checkmark. Day 2 has no
  /// "progress" backend feature yet (explicitly out of scope), so this is
  /// purely a local, in-memory flag for now.
  bool isCompleted;

  LessonModel({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.pdfUrl,
    required this.duration,
    required this.orderNumber,
    this.isCompleted = false,
  });

  factory LessonModel.fromJson(Map<String, dynamic> json) {
    return LessonModel(
      id: json['id'] as int,
      subjectId: json['subject_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      pdfUrl: json['pdf_url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      orderNumber: json['order_number'] as int? ?? 0,
    );
  }
}
