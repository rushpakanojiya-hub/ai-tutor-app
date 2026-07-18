import '../core/constants/api_constants.dart';
import '../models/user_model.dart';
import 'api_service.dart';

/// Result of a successful login, carrying both the token and the user.
class LoginResult {
  final String token;
  final UserModel user;

  LoginResult({required this.token, required this.user});
}

/// Talks to the backend's /api/auth/* endpoints. Contains no Flutter
/// widget/UI logic — that lives in AuthProvider and the screens.
class AuthService {
  final ApiService _api = ApiService();

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await _api.post(ApiConstants.register, {
      'name': name,
      'email': email,
      'password': password,
    });
  }

  /// Submits a teacher application. The account is created as "pending" -
  /// it cannot log in until an admin approves it (no file upload yet for
  /// resume/certificate - that needs a file storage service first).
  Future<void> applyAsTeacher({
    required String name,
    required String email,
    required String password,
    String phone = '',
    String qualification = '',
    String experience = '',
    String subjects = '',
    String bio = '',
  }) async {
    await _api.post(ApiConstants.teacherApply, {
      'name': name,
      'email': email,
      'password': password,
      'phone': phone,
      'qualification': qualification,
      'experience': experience,
      'subjects': subjects,
      'bio': bio,
    });
  }

  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post(ApiConstants.login, {
      'email': email,
      'password': password,
    });

    final rawToken = response['token'];
    if (rawToken is! String || rawToken.isEmpty) {
      throw Exception('Login failed: server did not return a valid token.');
    }

    final rawUser = response['user'];
    if (rawUser is! Map<String, dynamic>) {
      throw Exception('Login failed: server did not return valid user data.');
    }

    final user = UserModel.fromJson(rawUser);
    return LoginResult(token: rawToken, user: user);
  }

  Future<Map<String, dynamic>> fetchProfile() async {
    final response = await _api.get(ApiConstants.profile);
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Failed to load profile: unexpected server response.');
    }
    return data;
  }
}
