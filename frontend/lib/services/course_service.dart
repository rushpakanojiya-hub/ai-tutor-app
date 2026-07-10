import 'dart:io';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../models/category_model.dart';
import '../models/course_model.dart';
import 'api_service.dart';

/// Admin-only Course Management: covers Categories, Courses (subjects),
/// and Lessons - create/edit/delete/publish/reorder/upload. Every call
/// here hits an admin-gated backend endpoint; the backend itself
/// rejects non-admin callers with 403, this service does not duplicate
/// that check client-side.
class CourseService {
  final ApiService _api = ApiService();

  // --- Courses (subjects) ---

  Future<List<AdminCourseModel>> listCourses({String search = '', int? categoryId, String? status}) async {
    final response = await _api.get(ApiConstants.adminCourses(search: search, categoryId: categoryId, status: status));
    final list = response['data'] as List<dynamic>? ?? [];
    return list.map((json) => AdminCourseModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<int> createCourse({required int categoryId, required String name, String description = '', String thumbnail = ''}) async {
    final response = await _api.post(ApiConstants.subjects, {
      'category_id': categoryId,
      'name': name,
      'description': description,
      'thumbnail': thumbnail,
    });
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['id'] as int? ?? 0;
  }

  Future<void> updateCourse(int id, {int? categoryId, String? name, String? description, String? thumbnail, String? difficulty}) async {
    final body = <String, dynamic>{};
    if (categoryId != null) body['category_id'] = categoryId;
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (thumbnail != null) body['thumbnail'] = thumbnail;
    if (difficulty != null) body['difficulty'] = difficulty;
    await _api.put(ApiConstants.course(id), body);
  }

  Future<void> deleteCourse(int id) async {
    await _api.delete(ApiConstants.course(id));
  }

  Future<void> publishCourse(int id) async {
    await _api.post(ApiConstants.coursePublish(id), {});
  }

  Future<void> unpublishCourse(int id) async {
    await _api.post(ApiConstants.courseUnpublish(id), {});
  }

  // --- Categories ---

  Future<List<CategoryModel>> listCategories() async {
    final response = await _api.get(ApiConstants.categories);
    final list = response['data'] as List<dynamic>? ?? [];
    return list.map((json) => CategoryModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<int> createCategory(String name, {String icon = ''}) async {
    final response = await _api.post(ApiConstants.categories, {'name': name, 'icon': icon});
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['id'] as int? ?? 0;
  }

  Future<void> updateCategory(int id, {String? name, String? icon}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (icon != null) body['icon'] = icon;
    await _api.put(ApiConstants.categoryUpdate(id), body);
  }

  // --- Lessons ---

  Future<List<AdminLessonModel>> listLessons(int subjectId) async {
    final response = await _api.get(ApiConstants.subjectLessons(subjectId));
    final list = response['data'] as List<dynamic>? ?? [];
    return list.map((json) => AdminLessonModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<int> createLesson({required int subjectId, required String title, String description = '', int duration = 0, int orderNumber = 0}) async {
    final response = await _api.post(ApiConstants.lessonsCreate, {
      'subject_id': subjectId,
      'title': title,
      'description': description,
      'duration': duration,
      'order_number': orderNumber,
    });
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['id'] as int? ?? 0;
  }

  Future<void> updateLesson(int id, {String? title, String? description, int? duration}) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (duration != null) body['duration'] = duration;
    await _api.put(ApiConstants.lessonById(id), body);
  }

  Future<void> deleteLesson(int id) async {
    await _api.delete(ApiConstants.lessonById(id));
  }

  Future<void> reorderLessons(int subjectId, List<Map<String, int>> items) async {
    await _api.post(ApiConstants.lessonsReorder(subjectId), {'items': items});
  }

  Future<String> uploadLessonVideo(int lessonId, File file) async {
    final formData = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split(Platform.pathSeparator).last)});
    final response = await _api.postMultipart(ApiConstants.lessonUploadVideo(lessonId), formData);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['video_url'] as String? ?? '';
  }

  Future<String> uploadLessonPdf(int lessonId, File file) async {
    final formData = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split(Platform.pathSeparator).last)});
    final response = await _api.postMultipart(ApiConstants.lessonUploadPdf(lessonId), formData);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['pdf_url'] as String? ?? '';
  }

  Future<String> uploadLessonAssignment(int lessonId, File file) async {
    final formData = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split(Platform.pathSeparator).last)});
    final response = await _api.postMultipart(ApiConstants.lessonUploadAssignment(lessonId), formData);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['assignment_url'] as String? ?? '';
  }
}
