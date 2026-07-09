import '../core/constants/api_constants.dart';
import 'api_service.dart';

/// Handles the two Edit Profile actions: updating name+email, and
/// changing password. Separate from AuthService since these hit
/// /api/users/* rather than /api/auth/*.
class UserService {
  final ApiService _api = ApiService();

  Future<void> updateProfile({required String name, required String email}) async {
    await _api.put(ApiConstants.updateProfile, {'name': name, 'email': email});
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await _api.post(ApiConstants.changePassword, {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }
}
