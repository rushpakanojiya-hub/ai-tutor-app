import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Holds authentication state (token, current user, loading/error flags)
/// and exposes the actions screens call: register, login, logout, restore.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final StorageService _storage = StorageService();

  AuthStatus status = AuthStatus.unknown;
  UserModel? currentUser;
  bool isLoading = false;
  String? errorMessage;

  /// Called once at app startup to check for a previously saved session.
  Future<void> tryAutoLogin() async {
    final token = await _storage.getString(AppConstants.keyAuthToken);
    final userId = await _storage.getInt(AppConstants.keyUserId);
    final userName = await _storage.getString(AppConstants.keyUserName);
    final userRole = await _storage.getString(AppConstants.keyUserRole);

    if (token != null && userId != null && userName != null && userRole != null) {
      currentUser = UserModel(id: userId, name: userName, role: userRole);
      status = AuthStatus.authenticated;
    } else {
      status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    return _runGuarded(() async {
      await _authService.register(name: name, email: email, password: password);
    });
  }

  Future<bool> login({required String email, required String password}) async {
    return _runGuarded(() async {
      final result = await _authService.login(email: email, password: password);

      await _storage.setString(AppConstants.keyAuthToken, result.token);
      await _storage.setInt(AppConstants.keyUserId, result.user.id);
      await _storage.setString(AppConstants.keyUserName, result.user.name);
      await _storage.setString(AppConstants.keyUserRole, result.user.role);

      currentUser = result.user;
      status = AuthStatus.authenticated;
    });
  }

  Future<void> logout() async {
    await _storage.clearAll();
    currentUser = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Runs an async action with consistent loading/error state handling,
  /// so screens don't need to repeat try/catch/setState boilerplate.
  Future<bool> _runGuarded(Future<void> Function() action) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await action();
      isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      isLoading = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      isLoading = false;
      errorMessage = 'Something went wrong. Please try again.';
      notifyListeners();
      return false;
    }
  }
}