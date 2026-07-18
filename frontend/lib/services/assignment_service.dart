import '../core/constants/api_constants.dart';
import '../core/utils/safe_parse.dart';
import '../models/assignment_model.dart';
import 'api_service.dart';

class AssignmentService {
  final ApiService _api = ApiService();

  // --- Teacher ---

  Future<int> create({
    required int subjectId,
    required String title,
    required String description,
    required String instructions,
    String difficulty = 'medium',
    int estimatedMinutes = 30,
    int maxMarks = 10,
    int? passingMarks,
    DateTime? startDate,
    DateTime? dueDate,
  }) async {
    final response = await _api.post(ApiConstants.assignments, {
      'subject_id': subjectId,
      'title': title,
      'description': description,
      'instructions': instructions,
      'difficulty': difficulty,
      'estimated_minutes': estimatedMinutes,
      'max_marks': maxMarks,
      if (passingMarks != null) 'passing_marks': passingMarks,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (dueDate != null) 'due_date': dueDate.toIso8601String(),
    });
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Failed to create assignment: unexpected server response.');
    }
    return safeIntRequired(data['id'], 'id');
  }

  Future<GeneratedAssignmentDraft> generateWithAI({
    required int subjectId,
    required String topic,
    String difficulty = 'medium',
  }) async {
    final response = await _api.post(ApiConstants.assignmentGenerateAI, {
      'subject_id': subjectId,
      'topic': topic,
      'difficulty': difficulty,
    });
    return GeneratedAssignmentDraft.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<AssignmentModel>> fetchMine() async {
    final response = await _api.get(ApiConstants.myAssignments);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => AssignmentModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<void> publish(int id) async => _api.post(ApiConstants.assignmentPublish(id), {});
  Future<void> unpublish(int id) async => _api.post(ApiConstants.assignmentUnpublish(id), {});
  Future<void> close(int id) async => _api.post(ApiConstants.assignmentClose(id), {});
  Future<void> archive(int id) async => _api.post(ApiConstants.assignmentArchive(id), {});
  Future<void> delete(int id) async => _api.delete(ApiConstants.assignment(id));

  Future<AssignmentAnalyticsModel> fetchTeacherAnalytics() async {
    final response = await _api.get(ApiConstants.teacherAssignmentAnalytics);
    return AssignmentAnalyticsModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<AssignmentSubmissionModel>> fetchSubmissions(int assignmentId) async {
    final response = await _api.get(ApiConstants.assignmentSubmissions(assignmentId));
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => AssignmentSubmissionModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<void> reviewSubmission(int submissionId, {int? overrideScore, String feedback = ''}) async {
    await _api.post(ApiConstants.reviewSubmission(submissionId), {
      if (overrideScore != null) 'override_score': overrideScore,
      'feedback': feedback,
    });
  }

  // --- Student ---

  Future<AssignmentModel> fetchById(int id) async {
    final response = await _api.get(ApiConstants.assignment(id));
    return AssignmentModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<AssignmentModel>> fetchForSubject(int subjectId) async {
    final response = await _api.get(ApiConstants.subjectAssignments(subjectId));
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => AssignmentModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Every published assignment across every subject the student is
  /// enrolled in - powers the Assignments tab and Home dashboard card.
  Future<List<AssignmentModel>> fetchForStudent() async {
    final response = await _api.get(ApiConstants.assignmentsForStudent);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => AssignmentModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<void> saveDraft(int assignmentId, String text) async {
    await _api.post(ApiConstants.assignmentDraft(assignmentId), {'submission_text': text});
  }

  Future<AssignmentSubmissionModel> submit(int assignmentId, String text) async {
    final response = await _api.post(ApiConstants.assignmentSubmit(assignmentId), {'submission_text': text});
    return AssignmentSubmissionModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<AssignmentSubmissionModel?> fetchMySubmission(int assignmentId) async {
    final response = await _api.get(ApiConstants.mySubmission(assignmentId));
    final data = response['data'];
    if (data == null) return null;
    return AssignmentSubmissionModel.fromJson(data as Map<String, dynamic>);
  }

  Future<AssignmentSubmissionModel> retryEvaluation(int submissionId) async {
    final response = await _api.post(ApiConstants.retryEvaluation(submissionId), {});
    return AssignmentSubmissionModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  // --- Admin ---

  Future<List<AssignmentModel>> fetchAllForAdmin() async {
    final response = await _api.get(ApiConstants.adminAssignments);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => AssignmentModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<AssignmentAnalyticsModel> fetchAdminAnalytics() async {
    final response = await _api.get(ApiConstants.adminAssignmentAnalytics);
    return AssignmentAnalyticsModel.fromJson(response['data'] as Map<String, dynamic>);
  }
}
