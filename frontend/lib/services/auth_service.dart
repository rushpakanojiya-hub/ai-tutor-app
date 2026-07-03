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

  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post(ApiConstants.login, {
      'email': email,
      'password': password,
    });

    final token = response['token'] as String;
    final user = UserModel.fromJson(response['user'] as Map<String, dynamic>);
    return LoginResult(token: token, user: user);
  }

  Future<Map<String, dynamic>> fetchProfile() async {
    final response = await _api.get(ApiConstants.profile);
    return response['data'] as Map<String, dynamic>;
  }
}