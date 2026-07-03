import '../core/constants/api_constants.dart';
import '../models/subject_model.dart';
import 'api_service.dart';

/// Talks to the backend's /api/subjects and /api/categories/:id/subjects endpoints.
class SubjectService {
  final ApiService _api = ApiService();

  Future<List<SubjectModel>> fetchSubjectsByCategory(int categoryId) async {
    final response = await _api.get(ApiConstants.categorySubjects(categoryId));
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => SubjectModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<SubjectModel> fetchSubjectById(int subjectId) async {
    final response = await _api.get(ApiConstants.subjectById(subjectId));
    return SubjectModel.fromJson(response['data'] as Map<String, dynamic>);
  }
}
