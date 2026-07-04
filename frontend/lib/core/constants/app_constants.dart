/// App-wide constants that aren't related to networking.
class AppConstants {
  AppConstants._();

  static const String appName = 'AI Tutor';

  // SharedPreferences keys
  static const String keyAuthToken = 'auth_token';
  static const String keyUserId = 'user_id';
  static const String keyUserName = 'user_name';
  static const String keyUserRole = 'user_role';

  // Local-only "continue learning" tracking (no backend schema for this â€”
  // see LessonsScreen and DashboardScreen).
  static const String keyLastSubjectId = 'last_subject_id';
  static const String keyLastSubjectName = 'last_subject_name';
}
