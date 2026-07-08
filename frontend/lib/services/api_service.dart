import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/app_constants.dart';
import 'storage_service.dart';

/// A normalized exception so the UI never has to deal with raw DioException.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Thin wrapper around Dio: base URL, timeouts, auth header injection,
/// and consistent error translation (Part 9: Error Handling).
class ApiService {
  late final Dio _dio;
  final StorageService _storage = StorageService();

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.getString(AppConstants.keyAuthToken);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(path, data: data);
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translateError(e);
    }
  }

  Future<Map<String, dynamic>> get(String path) async {
    try {
      final response = await _dio.get(path);
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translateError(e);
    }
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put(path, data: data);
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translateError(e);
    }
  }

  Future<Map<String, dynamic>> delete(String path) async {
    try {
      final response = await _dio.delete(path);
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translateError(e);
    }
  }

  /// For file uploads (Class Resources) - pass a Dio FormData built with
  /// FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: name)}).
  /// onProgress receives a 0.0-1.0 fraction if provided.
  Future<Map<String, dynamic>> postMultipart(String path, FormData formData, {void Function(double)? onProgress}) async {
    try {
      final response = await _dio.post(
        path,
        data: formData,
        onSendProgress: onProgress == null
            ? null
            : (sent, total) {
                if (total > 0) onProgress(sent / total);
              },
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translateError(e);
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  ApiException _translateError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException('Request timed out. Please check your internet connection.');
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiException('Unable to reach the server. Please check your network.');
    }

    final response = e.response;
    if (response != null) {
      final data = response.data;
      String message = 'Something went wrong. Please try again.';
      if (data is Map && data['message'] != null) {
        message = data['message'].toString();
      }
      return ApiException(message, statusCode: response.statusCode);
    }

    return ApiException('Unexpected error occurred. Please try again.');
  }
}
