class LiveClassModel {
  final int id;
  final int teacherId;
  final String teacherName;
  final int? subjectId;
  final String subjectName;
  final int? lessonId;
  final String lessonTitle;
  final String title;
  final String description;
  final String classDate; // YYYY-MM-DD
  final String startTime; // HH:MM:SS
  final String endTime;
  final int? maxStudents;
  final bool isPublic;
  final bool hasPassword;
  final bool recordClass;
  final String status; // scheduled | completed | cancelled | missed
  final String meetingStatus; // not_started | live | ended
  final bool locked;
  final DateTime createdAt;

  LiveClassModel({
    required this.id,
    required this.teacherId,
    required this.teacherName,
    this.subjectId,
    required this.subjectName,
    this.lessonId,
    required this.lessonTitle,
    required this.title,
    required this.description,
    required this.classDate,
    required this.startTime,
    required this.endTime,
    this.maxStudents,
    required this.isPublic,
    required this.hasPassword,
    required this.recordClass,
    required this.status,
    this.meetingStatus = 'not_started',
    this.locked = false,
    required this.createdAt,
  });

  DateTime? get dateTime {
    try {
      final parts = classDate.split('-').map(int.parse).toList();
      final timeParts = startTime.split(':').map(int.parse).toList();
      return DateTime(parts[0], parts[1], parts[2], timeParts[0], timeParts[1]);
    } catch (_) {
      return null;
    }
  }

  DateTime? get endDateTime {
    try {
      final parts = classDate.split('-').map(int.parse).toList();
      final timeParts = endTime.split(':').map(int.parse).toList();
      return DateTime(parts[0], parts[1], parts[2], timeParts[0], timeParts[1]);
    } catch (_) {
      return null;
    }
  }

  factory LiveClassModel.fromJson(Map<String, dynamic> json) {
    return LiveClassModel(
      id: json['id'] as int,
      teacherId: json['teacher_id'] as int? ?? 0,
      teacherName: json['teacher_name'] as String? ?? '',
      subjectId: json['subject_id'] as int?,
      subjectName: json['subject_name'] as String? ?? '',
      lessonId: json['lesson_id'] as int?,
      lessonTitle: json['lesson_title'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      classDate: json['class_date'] as String? ?? '',
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String? ?? '',
      maxStudents: json['max_students'] as int?,
      isPublic: json['is_public'] as bool? ?? true,
      hasPassword: json['has_password'] as bool? ?? false,
      recordClass: json['record_class'] as bool? ?? false,
      status: json['status'] as String? ?? 'scheduled',
      meetingStatus: json['meeting_status'] as String? ?? 'not_started',
      locked: json['locked'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class AttendanceRecord {
  final int studentId;
  final String studentName;
  final DateTime checkedInAt;
  final String status; // present | late

  AttendanceRecord({required this.studentId, required this.studentName, required this.checkedInAt, required this.status});

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      studentId: json['student_id'] as int,
      studentName: json['student_name'] as String? ?? '',
      checkedInAt: DateTime.tryParse(json['checked_in_at'] as String? ?? '') ?? DateTime.now(),
      status: json['status'] as String? ?? 'present',
    );
  }
}

class MyAttendance {
  final bool checkedIn;
  final String? status;
  final DateTime? checkedInAt;

  MyAttendance({required this.checkedIn, this.status, this.checkedInAt});

  factory MyAttendance.fromJson(Map<String, dynamic> json) {
    return MyAttendance(
      checkedIn: json['checked_in'] as bool? ?? false,
      status: json['status'] as String?,
      checkedInAt: json['checked_in_at'] != null ? DateTime.tryParse(json['checked_in_at'] as String) : null,
    );
  }
}

class AttendanceSummary {
  final int totalCompletedClasses;
  final int attendedCount;
  final double percentage;

  AttendanceSummary({required this.totalCompletedClasses, required this.attendedCount, required this.percentage});

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      totalCompletedClasses: json['total_completed_classes'] as int? ?? 0,
      attendedCount: json['attended_count'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Everything the LiveKit client needs to connect - returned by both
/// Start (teacher) and Join (student).
class MeetingSession {
  final String token;
  final String url;
  final String roomName;

  MeetingSession({required this.token, required this.url, required this.roomName});

  factory MeetingSession.fromJson(Map<String, dynamic> json) {
    return MeetingSession(
      token: json['token'] as String? ?? '',
      url: json['url'] as String? ?? '',
      roomName: json['room_name'] as String? ?? '',
    );
  }
}

/// A teacher-uploaded file (PDF/PPT/image/doc/video) attached to a live
/// class, hosted on Cloudinary.
class ClassResourceModel {
  final int id;
  final int liveClassId;
  final String fileName;
  final String fileType; // pdf | ppt | doc | xls | image | video | file
  final String fileUrl;
  final int fileSizeBytes;
  final DateTime uploadedAt;

  ClassResourceModel({
    required this.id,
    required this.liveClassId,
    required this.fileName,
    required this.fileType,
    required this.fileUrl,
    required this.fileSizeBytes,
    required this.uploadedAt,
  });

  factory ClassResourceModel.fromJson(Map<String, dynamic> json) {
    return ClassResourceModel(
      id: json['id'] as int? ?? 0,
      liveClassId: json['live_class_id'] as int? ?? 0,
      fileName: json['file_name'] as String? ?? '',
      fileType: json['file_type'] as String? ?? 'file',
      fileUrl: json['file_url'] as String? ?? '',
      fileSizeBytes: json['file_size_bytes'] as int? ?? 0,
      uploadedAt: DateTime.tryParse(json['uploaded_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
