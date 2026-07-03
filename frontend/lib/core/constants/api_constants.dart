/// Centralized API configuration so base URLs and endpoint paths
/// only ever need to change in one place.
class ApiConstants {
  ApiConstants._();

  /// Android emulator maps 10.0.2.2 to the host machine's localhost.
  /// - Physical device / real backend: replace with your machine's LAN IP
  ///   or your deployed Render URL, e.g. https://your-app.onrender.com
  /// - iOS simulator: use http://localhost:8080
  static const String baseUrl = 'http://192.168.1.14:8080/api';

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String profile = '/auth/profile';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
