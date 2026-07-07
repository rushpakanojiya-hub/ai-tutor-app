import '../core/constants/api_constants.dart';
import '../models/admin_models.dart';
import 'api_service.dart';

/// Talks to the admin-only /api/admin/* and /api/auth/admin/* endpoints.
/// Every call requires the signed-in user to have role == 'admin' -
/// the backend enforces this (middleware.RequireAdmin), this service just
/// makes the calls.
class AdminService {
  final ApiService _api = ApiService();

  Future<AdminDashboardStats> fetchDashboardStats() async {
    final response = await _api.get(ApiConstants.adminDashboard);
    return AdminDashboardStats.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<TeacherApplicationModel>> fetchPendingTeachers() async {
    final response = await _api.get(ApiConstants.adminPendingTeachers);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => TeacherApplicationModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<void> approveTeacher(int id) async {
    await _api.post(ApiConstants.adminApproveTeacher(id), {});
  }

  Future<void> rejectTeacher(int id) async {
    await _api.post(ApiConstants.adminRejectTeacher(id), {});
  }
}
