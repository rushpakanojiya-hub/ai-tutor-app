/// Plain data model for a PDF note attached to a lesson.
class NoteModel {
  final int id;
  final int lessonId;
  final String title;
  final String pdfUrl;

  NoteModel({
    required this.id,
    required this.lessonId,
    required this.title,
    required this.pdfUrl,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as int,
      lessonId: json['lesson_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      pdfUrl: json['pdf_url'] as String? ?? '',
    );
  }
}
