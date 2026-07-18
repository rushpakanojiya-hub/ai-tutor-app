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

  // QA fix ("Router rebuild issue"): app_router.dart used to pass this
  // whole AuthProvider as GoRouter's refreshListenable, so EVERY
  // notifyListeners() call here - including ones that only change
  // isLoading for a button spinner, with status untouched - triggered a
  // full router redirect re-evaluation and route rebuild. statusNotifier
  // is a dedicated ValueNotifier that only fires when `status` itself
  // actually changes (ValueNotifier's built-in equality check), and
  // app_router.dart now listens to this instead of the whole provider.
  final ValueNotifier<AuthStatus> statusNotifier = ValueNotifier(AuthStatus.unknown);

  void _setStatus(AuthStatus newStatus) {
    status = newStatus;
    statusNotifier.value = newStatus;
  }

  @override
  void dispose() {
    statusNotifier.dispose();
    super.dispose();
  }

  // --- Editable name (additive) ---
  //
  // Updates the cached user (so the rest of the app reflects the new
  // name immediately, no re-login needed) and persists it to secure
  // storage, same as tryAutoLogin reads it back from.
  Future<void> updateLocalName(String name) async {
    if (currentUser != null) {
      currentUser = UserModel(id: currentUser!.id, name: name, role: currentUser!.role);
      await _storage.setString(AppConstants.keyUserName, name);
      notifyListeners();
    }
  }

  /// Called once at app startup to check for a previously saved session.
  ///
  /// QA fix ("Splash screen disappears in milliseconds"): the storage
  /// reads below finish almost instantly, and _setStatus() is what
  /// actually triggers GoRouter's redirect via statusNotifier - so
  /// wrapping the CALLER's await in a delay (e.g. in splash_screen.dart)
  /// doesn't help, since the status change itself already fired before
  /// that delay even starts. The minimum-duration wait has to live here,
  /// wrapping the status change directly - the real storage check and a
  /// 2-second timer run together, and whichever finishes last is what
  /// _setStatus waits on.
  Future<void> tryAutoLogin() async {
    String? token;
    int? userId;
    String? userName;
    String? userRole;

    Future<void> readSession() async {
      token = await _storage.getString(AppConstants.keyAuthToken);
      userId = await _storage.getInt(AppConstants.keyUserId);
      userName = await _storage.getString(AppConstants.keyUserName);
      userRole = await _storage.getString(AppConstants.keyUserRole);
    }

    await Future.wait([
      readSession(),
      Future.delayed(const Duration(seconds: 2)),
    ]);

    if (token != null && userId != null && userName != null && userRole != null) {
      currentUser = UserModel(id: userId!, name: userName!, role: userRole!);
      _setStatus(AuthStatus.authenticated);
    } else {
      _setStatus(AuthStatus.unauthenticated);
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

  /// Submits a teacher application - the account starts "pending" and
  /// can't log in until an admin approves it.
  Future<bool> applyAsTeacher({
    required String name,
    required String email,
    required String password,
    String phone = '',
    String qualification = '',
    String experience = '',
    String subjects = '',
    String bio = '',
  }) async {
    return _runGuarded(() async {
      await _authService.applyAsTeacher(
        name: name,
        email: email,
        password: password,
        phone: phone,
        qualification: qualification,
        experience: experience,
        subjects: subjects,
        bio: bio,
      );
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
      _setStatus(AuthStatus.authenticated);
    });
  }

  Future<void> logout() async {
    await _storage.clearAll();
    currentUser = null;
    _setStatus(AuthStatus.unauthenticated);
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