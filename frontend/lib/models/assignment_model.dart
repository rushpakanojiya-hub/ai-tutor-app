class AssignmentModel {
  final int id;
  final int teacherId;
  final String teacherName;
  final int? subjectId;
  final String subjectName;
  final String title;
  final String description;
  final String instructions;
  final String difficulty;
  final int? estimatedMinutes;
  final int maxMarks;
  final int? passingMarks;
  final DateTime? startDate;
  final DateTime? dueDate;
  final String status; // draft | published | unpublished | closed | archived
  final String myStatus; // student-facing: not_started | draft | submitted | evaluated | returned
  final int submissionCount;
  final DateTime createdAt;

  AssignmentModel({
    required this.id,
    required this.teacherId,
    required this.teacherName,
    this.subjectId,
    required this.subjectName,
    required this.title,
    required this.description,
    required this.instructions,
    required this.difficulty,
    this.estimatedMinutes,
    required this.maxMarks,
    this.passingMarks,
    this.startDate,
    this.dueDate,
    required this.status,
    this.myStatus = 'not_started',
    required this.submissionCount,
    required this.createdAt,
  });

  factory AssignmentModel.fromJson(Map<String, dynamic> json) {
    return AssignmentModel(
      id: json['id'] as int,
      teacherId: json['teacher_id'] as int? ?? 0,
      teacherName: json['teacher_name'] as String? ?? '',
      subjectId: json['subject_id'] as int?,
      subjectName: json['subject_name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? 'medium',
      estimatedMinutes: json['estimated_minutes'] as int?,
      maxMarks: json['max_marks'] as int? ?? 10,
      passingMarks: json['passing_marks'] as int?,
      startDate: json['start_date'] != null ? DateTime.tryParse(json['start_date'] as String) : null,
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'] as String) : null,
      status: json['status'] as String? ?? 'draft',
      myStatus: json['my_status'] as String? ?? 'not_started',
      submissionCount: json['submission_count'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class GeneratedAssignmentDraft {
  final String title;
  final String description;
  final String instructions;
  final int estimatedMinutes;

  GeneratedAssignmentDraft({
    required this.title,
    required this.description,
    required this.instructions,
    required this.estimatedMinutes,
  });

  factory GeneratedAssignmentDraft.fromJson(Map<String, dynamic> json) {
    return GeneratedAssignmentDraft(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      estimatedMinutes: json['estimated_minutes'] as int? ?? 30,
    );
  }
}

class AssignmentEvaluationModel {
  final int? aiScore;
  final int? maxScore;
  final double? percentage;
  final List<String> strengths;
  final List<String> weaknesses;
  final List<String> missingConcepts;
  final String suggestions;
  final int? teacherOverrideScore;
  final String teacherFeedback;
  final bool reviewedByTeacher;

  AssignmentEvaluationModel({
    this.aiScore,
    this.maxScore,
    this.percentage,
    required this.strengths,
    required this.weaknesses,
    required this.missingConcepts,
    required this.suggestions,
    this.teacherOverrideScore,
    required this.teacherFeedback,
    required this.reviewedByTeacher,
  });

  factory AssignmentEvaluationModel.fromJson(Map<String, dynamic> json) {
    return AssignmentEvaluationModel(
      aiScore: json['ai_score'] as int?,
      maxScore: json['max_score'] as int?,
      percentage: (json['percentage'] as num?)?.toDouble(),
      strengths: (json['strengths'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      weaknesses: (json['weaknesses'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      missingConcepts: (json['missing_concepts'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      suggestions: json['suggestions'] as String? ?? '',
      teacherOverrideScore: json['teacher_override_score'] as int?,
      teacherFeedback: json['teacher_feedback'] as String? ?? '',
      reviewedByTeacher: json['reviewed_by_teacher'] as bool? ?? false,
    );
  }
}

class AssignmentSubmissionModel {
  final int id;
  final int assignmentId;
  final int studentId;
  final String studentName;
  final String submissionText;
  final String status; // draft | submitted | under_review | evaluated | returned
  final DateTime? submittedAt;
  final AssignmentEvaluationModel? evaluation;

  AssignmentSubmissionModel({
    required this.id,
    required this.assignmentId,
    required this.studentId,
    required this.studentName,
    required this.submissionText,
    required this.status,
    this.submittedAt,
    this.evaluation,
  });

  factory AssignmentSubmissionModel.fromJson(Map<String, dynamic> json) {
    return AssignmentSubmissionModel(
      id: json['id'] as int,
      assignmentId: json['assignment_id'] as int,
      studentId: json['student_id'] as int,
      studentName: json['student_name'] as String? ?? '',
      submissionText: json['submission_text'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      submittedAt: json['submitted_at'] != null ? DateTime.tryParse(json['submitted_at'] as String) : null,
      evaluation: json['evaluation'] != null ? AssignmentEvaluationModel.fromJson(json['evaluation'] as Map<String, dynamic>) : null,
    );
  }
}

class AssignmentAnalyticsModel {
  final int totalAssignments;
  final int publishedAssignments;
  final int totalSubmissions;
  final int evaluatedSubmissions;
  final double averageScorePercent;

  AssignmentAnalyticsModel({
    required this.totalAssignments,
    required this.publishedAssignments,
    required this.totalSubmissions,
    required this.evaluatedSubmissions,
    required this.averageScorePercent,
  });

  factory AssignmentAnalyticsModel.fromJson(Map<String, dynamic> json) {
    return AssignmentAnalyticsModel(
      totalAssignments: json['total_assignments'] as int? ?? 0,
      publishedAssignments: json['published_assignments'] as int? ?? 0,
      totalSubmissions: json['total_submissions'] as int? ?? 0,
      evaluatedSubmissions: json['evaluated_submissions'] as int? ?? 0,
      averageScorePercent: (json['average_score_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
