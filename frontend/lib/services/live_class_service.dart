import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../models/live_class_model.dart';
import 'api_service.dart';

class LiveClassService {
  final ApiService _api = ApiService();

  Future<int> create({
    required int subjectId,
    int? lessonId,
    required String title,
    required String description,
    required String classDate,
    required String startTime,
    required String endTime,
    int? maxStudents,
    bool isPublic = true,
    String meetingPassword = '',
    bool recordClass = false,
  }) async {
    final response = await _api.post(ApiConstants.liveClasses, {
      'subject_id': subjectId,
      if (lessonId != null) 'lesson_id': lessonId,
      'title': title,
      'description': description,
      'class_date': classDate,
      'start_time': startTime,
      'end_time': endTime,
      if (maxStudents != null) 'max_students': maxStudents,
      'is_public': isPublic,
      'meeting_password': meetingPassword,
      'record_class': recordClass,
    });
    return (response['data'] as Map<String, dynamic>)['id'] as int;
  }

  Future<void> cancel(int id) async => _api.post(ApiConstants.liveClassCancel(id), {});
  Future<void> markCompleted(int id) async => _api.post(ApiConstants.liveClassComplete(id), {});
  Future<void> delete(int id) async => _api.delete(ApiConstants.liveClass(id));

  Future<List<LiveClassModel>> fetchMine() async {
    final response = await _api.get(ApiConstants.myLiveClasses);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => LiveClassModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<LiveClassModel>> fetchForStudent() async {
    final response = await _api.get(ApiConstants.liveClassesForStudent);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => LiveClassModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<LiveClassModel>> fetchAllForAdmin() async {
    final response = await _api.get(ApiConstants.adminLiveClasses);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => LiveClassModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<void> adminCancel(int id) async => _api.post(ApiConstants.adminLiveClassCancel(id), {});

  Future<String> checkIn(int classId) async {
    final response = await _api.post(ApiConstants.liveClassCheckIn(classId), {});
    return (response['data'] as Map<String, dynamic>)['status'] as String? ?? 'present';
  }

  Future<MyAttendance> fetchMyAttendance(int classId) async {
    final response = await _api.get(ApiConstants.liveClassMyAttendance(classId));
    return MyAttendance.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<AttendanceRecord>> fetchAttendanceForClass(int classId) async {
    final response = await _api.get(ApiConstants.liveClassAttendance(classId));
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => AttendanceRecord.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<AttendanceSummary> fetchAttendanceSummary() async {
    final response = await _api.get(ApiConstants.liveClassAttendanceSummary);
    return AttendanceSummary.fromJson(response['data'] as Map<String, dynamic>);
  }

  // --- Real video session (LiveKit) ---

  Future<MeetingSession> startClass(int classId) async {
    final response = await _api.post(ApiConstants.liveClassStart(classId), {});
    return MeetingSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<MeetingSession> joinClass(int classId) async {
    final response = await _api.post(ApiConstants.liveClassJoin(classId), {});
    return MeetingSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<void> endClass(int classId) async => _api.post(ApiConstants.liveClassEnd(classId), {});

  Future<String> fetchMeetingStatus(int classId) async {
    final response = await _api.get(ApiConstants.liveClassMeetingStatus(classId));
    return (response['data'] as Map<String, dynamic>)['meeting_status'] as String? ?? 'not_started';
  }

  // --- Teacher moderation ---

  Future<void> muteParticipant(int classId, String identity) async => _api.post(ApiConstants.liveClassMute(classId, identity), {});
  Future<void> removeParticipant(int classId, String identity) async => _api.post(ApiConstants.liveClassRemove(classId, identity), {});
  Future<void> muteAll(int classId) async => _api.post(ApiConstants.liveClassMuteAll(classId), {});
  Future<void> lockRoom(int classId) async => _api.post(ApiConstants.liveClassLock(classId), {});
  Future<void> unlockRoom(int classId) async => _api.post(ApiConstants.liveClassUnlock(classId), {});

  // --- Class Resources (GCS-backed file uploads) ---

  Future<ClassResourceModel> uploadResource(int classId, String filePath, String fileName, {void Function(double)? onProgress}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _api.postMultipart(ApiConstants.liveClassResources(classId), formData, onProgress: onProgress);
    return ClassResourceModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<ClassResourceModel>> fetchResources(int classId) async {
    final response = await _api.get(ApiConstants.liveClassResources(classId));
    final list = response['data'] as List<dynamic>? ?? [];
    return list.map((e) => ClassResourceModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteResource(int classId, int resourceId) async {
    await _api.delete(ApiConstants.liveClassResourceDelete(classId, resourceId));
  }
}
