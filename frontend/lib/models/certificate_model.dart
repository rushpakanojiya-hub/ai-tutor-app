class CertificateModel {
  final int id;
  final String certificateCode;
  final int studentId;
  final String studentName;
  final int subjectId;
  final String courseName;
  final String subjectName;
  final String instructorName;
  final double finalScore;
  final String grade;
  final String completionDate;
  final DateTime issueDate;

  CertificateModel({
    required this.id,
    required this.certificateCode,
    required this.studentId,
    required this.studentName,
    required this.subjectId,
    required this.courseName,
    required this.subjectName,
    required this.instructorName,
    required this.finalScore,
    required this.grade,
    required this.completionDate,
    required this.issueDate,
  });

  factory CertificateModel.fromJson(Map<String, dynamic> json) {
    return CertificateModel(
      id: json['id'] as int,
      certificateCode: json['certificate_code'] as String? ?? '',
      studentId: json['student_id'] as int,
      studentName: json['student_name'] as String? ?? '',
      subjectId: json['subject_id'] as int,
      courseName: json['course_name'] as String? ?? '',
      subjectName: json['subject_name'] as String? ?? '',
      instructorName: json['instructor_name'] as String? ?? '',
      finalScore: (json['final_score'] as num?)?.toDouble() ?? 0.0,
      grade: json['grade'] as String? ?? '',
      completionDate: json['completion_date'] as String? ?? '',
      issueDate: DateTime.tryParse(json['issue_date'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
