import '../core/constants/api_constants.dart';
import '../models/leaderboard_entry_model.dart';
import '../models/student_class_section_model.dart';
import 'api_service.dart';

class LeaderboardService {
  final ApiService _api = ApiService();

  Future<List<LeaderboardEntry>> fetch({String period = 'overall', String? classFilter, String? section}) async {
    final response = await _api.get(ApiConstants.leaderboard(period: period, classFilter: classFilter, section: section));
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => LeaderboardEntry.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<StudentClassSectionModel>> listStudents() async {
    final response = await _api.get(ApiConstants.adminStudents);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => StudentClassSectionModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<void> assignClassSection(int studentId, {required String classValue, required String section}) async {
    await _api.put(ApiConstants.assignClassSection(studentId), {'class': classValue, 'section': section});
  }
}
