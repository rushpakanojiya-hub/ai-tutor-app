# apply_frontend_round3_fixes.ps1
# Run from your FRONTEND project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\frontend)
# Writes: live_class_model.dart (safe shortStartTime/shortEndTime getters),
# 3 screens using unguarded substring(0,5) on start/end time, 2 more video/Chewie
# controller leaks, and 3 missing mounted checks in create_live_class_screen.dart.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying frontend round-3 fixes in $root" -ForegroundColor Cyan

# --- lib/models/live_class_model.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/models") | Out-Null
$content_lib_models_live_class_model_dart = @'
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

  // BUG FIX: several screens did `startTime.substring(0, 5)` /
  // `endTime.substring(0, 5)` directly to show "HH:MM" - startTime/
  // endTime default to '' when the backend omits the field (see
  // fromJson below), and '' (or anything shorter than 5 chars) throws
  // a RangeError. These shared getters fall back to the raw string
  // instead of crashing; use them instead of substring(0, 5) directly.
  String get shortStartTime => startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
  String get shortEndTime => endTime.length >= 5 ? endTime.substring(0, 5) : endTime;

  factory LiveClassModel.fromJson(Map<String, dynamic> json) {
    return LiveClassModel(
      id: json['id'] as int? ?? 0,
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
      studentId: json['student_id'] as int? ?? 0,
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

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/models/live_class_model.dart"), $content_lib_models_live_class_model_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/models/live_class_model.dart" -ForegroundColor Green

# --- lib/screens/liveclass/admin_live_classes_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/liveclass") | Out-Null
$content_lib_screens_liveclass_admin_live_classes_screen_dart = @'
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/live_class_model.dart';
import '../../services/live_class_service.dart';
import '../../widgets/skeleton_box.dart';

/// Admin's platform-wide view of every scheduled class - view-only.
class AdminLiveClassesScreen extends StatefulWidget {
  const AdminLiveClassesScreen({super.key});

  @override
  State<AdminLiveClassesScreen> createState() => _AdminLiveClassesScreenState();
}

class _AdminLiveClassesScreenState extends State<AdminLiveClassesScreen> {
  final LiveClassService _service = LiveClassService();
  List<LiveClassModel> _classes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _classes = await _service.fetchAllForAdmin();
    } catch (e) {
      _error = 'Could not load classes.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _cancel(LiveClassModel c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel class?'),
        content: Text('"${c.title}" will be cancelled and students notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel Class', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.adminCancel(c.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to cancel class.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Live Classes Monitoring')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: const [SkeletonBox(height: 100, borderRadius: BorderRadius.all(Radius.circular(18)))])
            : _error != null
                ? ListView(children: [const SizedBox(height: 80), Center(child: Text(_error!))])
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _classes.length,
                    itemBuilder: (context, index) {
                      final c = _classes[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text('${c.teacherName} \u2022 ${c.subjectName} \u2022 ${c.status}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            Text('${c.classDate} \u2022 ${c.shortStartTime}-${c.shortEndTime}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            if (c.status == 'scheduled') ...[
                              const SizedBox(height: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                                onPressed: () => _cancel(c),
                                child: const Text('Cancel Class'),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/liveclass/admin_live_classes_screen.dart"), $content_lib_screens_liveclass_admin_live_classes_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/liveclass/admin_live_classes_screen.dart" -ForegroundColor Green

# --- lib/screens/liveclass/my_live_classes_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/liveclass") | Out-Null
$content_lib_screens_liveclass_my_live_classes_screen_dart = @'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/live_class_model.dart';
import '../../services/live_class_service.dart';
import '../../widgets/skeleton_box.dart';
import 'live_class_room_screen.dart';

/// Teacher's scheduled classes with quick stats, plus attendance viewing
/// per class. Cancel/mark-completed/delete are real actions against the
/// real backend; there's no "Edit" form yet (create/cancel/complete
/// cover the core workflow for this pass).
class MyLiveClassesScreen extends StatefulWidget {
  const MyLiveClassesScreen({super.key});

  @override
  State<MyLiveClassesScreen> createState() => _MyLiveClassesScreenState();
}

class _MyLiveClassesScreenState extends State<MyLiveClassesScreen> {
  final LiveClassService _service = LiveClassService();
  List<LiveClassModel> _classes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _classes = await _service.fetchMine();
    } catch (e) {
      _error = 'Could not load your classes.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action failed. Please try again.')));
    }
  }

  Future<void> _delete(LiveClassModel c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete class?'),
        content: Text('"${c.title}" will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true) _action(() => _service.delete(c.id));
  }

  Future<void> _endClassDirectly(LiveClassModel c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this class?'),
        content: const Text('This will disconnect all students currently in the call.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End Class', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.endClass(c.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to end class.')));
    }
  }

  Future<void> _startClass(LiveClassModel c) async {
    try {
      final session = await _service.startClass(c.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveClassRoomScreen(
            classId: c.id,
            url: session.url,
            token: session.token,
            classTitle: c.title,
            subjectName: c.subjectName,
            lessonTitle: c.lessonTitle,
            description: c.description,
            subjectId: c.subjectId,
            scheduledStart: c.dateTime,
            scheduledEnd: c.endDateTime,
            isTeacher: true,
            onEndClass: () => _service.endClass(c.id),
          ),
        ),
      );
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start the class. Please try again.')));
    }
  }

  Future<void> _viewAttendance(LiveClassModel c) async {
    List<AttendanceRecord> records = [];
    String? error;
    try {
      records = await _service.fetchAttendanceForClass(c.id);
    } catch (e) {
      error = 'Could not load attendance.';
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attendance: ${c.title}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            if (error != null)
              Text(error, style: const TextStyle(color: AppColors.error))
            else if (records.isEmpty)
              const Text('No students have checked in yet.', style: TextStyle(color: AppColors.textSecondary))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final r = records[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.studentName),
                      subtitle: Text('Checked in ${r.checkedInAt.hour.toString().padLeft(2, '0')}:${r.checkedInAt.minute.toString().padLeft(2, '0')}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (r.status == 'late' ? AppColors.orange : AppColors.green).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(r.status, style: TextStyle(color: r.status == 'late' ? AppColors.orange : AppColors.green, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.green;
      case 'cancelled':
        return AppColors.error;
      case 'missed':
        return AppColors.textSecondary;
      default:
        return AppColors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayStr = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final todayCount = _classes.where((c) => c.classDate == todayStr && c.status == 'scheduled').length;
    final upcomingCount = _classes.where((c) => c.status == 'scheduled').length;
    final completedCount = _classes.where((c) => c.status == 'completed').length;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('My Live Classes')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.purple,
        onPressed: () async {
          await context.push('/create-live-class');
          _load();
        },
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: List.generate(3, (_) => const Padding(padding: EdgeInsets.all(16), child: SkeletonBox(height: 100, borderRadius: BorderRadius.all(Radius.circular(18))))))
            : _error != null
                ? ListView(children: [const SizedBox(height: 80), Center(child: Text(_error!)), Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry')))])
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Row(
                        children: [
                          Expanded(child: _statCard('Today', '$todayCount', AppColors.purple)),
                          const SizedBox(width: 10),
                          Expanded(child: _statCard('Upcoming', '$upcomingCount', AppColors.blue)),
                          const SizedBox(width: 10),
                          Expanded(child: _statCard('Completed', '$completedCount', AppColors.green)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_classes.isEmpty)
                        const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No classes scheduled yet. Tap + to schedule one.', style: TextStyle(color: AppColors.textSecondary))))
                      else
                        ..._classes.map((c) => Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: _statusColor(c.status).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                                        child: Text(c.status, style: TextStyle(color: _statusColor(c.status), fontSize: 10, fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${c.subjectName} \u2022 ${c.classDate} \u2022 ${c.shortStartTime}-${c.shortEndTime}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (c.status == 'scheduled' && c.meetingStatus == 'live')
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                                          onPressed: () => _endClassDirectly(c),
                                          icon: const Icon(Icons.call_end_rounded, size: 18, color: Colors.white),
                                          label: const Text('End Class', style: TextStyle(color: Colors.white)),
                                        )
                                      else if (c.status == 'scheduled' && c.meetingStatus == 'not_started')
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.green),
                                          onPressed: () => _startClass(c),
                                          icon: const Icon(Icons.videocam_rounded, size: 18, color: Colors.white),
                                          label: const Text('Start Class', style: TextStyle(color: Colors.white)),
                                        )
                                      else if (c.status == 'scheduled' && c.meetingStatus == 'ended')
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(color: AppColors.pageBackground, borderRadius: BorderRadius.circular(8)),
                                          child: const Text('Class session ended', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                        ),
                                      OutlinedButton(onPressed: () => _viewAttendance(c), child: const Text('View Attendance')),
                                      if (c.status == 'scheduled') ...[
                                        OutlinedButton(onPressed: () => _action(() => _service.markCompleted(c.id)), child: const Text('Mark Completed')),
                                        OutlinedButton(onPressed: () => _action(() => _service.cancel(c.id)), child: const Text('Cancel Class')),
                                      ],
                                      OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: AppColors.error), onPressed: () => _delete(c), child: const Text('Delete')),
                                    ],
                                  ),
                                ],
                              ),
                            )),
                    ],
                  ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/liveclass/my_live_classes_screen.dart"), $content_lib_screens_liveclass_my_live_classes_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/liveclass/my_live_classes_screen.dart" -ForegroundColor Green

# --- lib/screens/liveclass/waiting_room_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/liveclass") | Out-Null
$content_lib_screens_liveclass_waiting_room_screen_dart = @'
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/live_class_model.dart';
import '../../services/live_class_service.dart';
import 'live_class_room_screen.dart';

/// Shown to a student when they try to join a class the teacher hasn't
/// started yet. Polls meeting status every few seconds and automatically
/// enters the real room the moment the teacher starts it - no need for
/// the student to tap Join again.
class WaitingRoomScreen extends StatefulWidget {
  final LiveClassModel liveClass;

  const WaitingRoomScreen({super.key, required this.liveClass});

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  final LiveClassService _service = LiveClassService();
  Timer? _poller;
  Timer? _ticker;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _poller = Timer.periodic(const Duration(seconds: 4), (_) => _checkStatus());
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (_navigating) return;
    try {
      final status = await _service.fetchMeetingStatus(widget.liveClass.id);
      if (status == 'live' && mounted) {
        _navigating = true;
        final session = await _service.joinClass(widget.liveClass.id);
        if (!mounted) return;
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LiveClassRoomScreen(
              classId: widget.liveClass.id,
              url: session.url,
              token: session.token,
              classTitle: widget.liveClass.title,
              subjectName: widget.liveClass.subjectName,
              lessonTitle: widget.liveClass.lessonTitle,
              description: widget.liveClass.description,
              subjectId: widget.liveClass.subjectId,
              scheduledStart: widget.liveClass.dateTime,
              scheduledEnd: widget.liveClass.endDateTime,
              isTeacher: false,
            ),
          ),
        );
      }
    } catch (_) {
      _navigating = false;
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _countdownText() {
    final dt = widget.liveClass.dateTime;
    if (dt == null) return '';
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'Starting any moment now';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (h > 0) return 'Starts in ${h}h ${m}m';
    if (m > 0) return 'Starts in ${m}m ${s}s';
    return 'Starts in ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.liveClass;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white70),
              const SizedBox(height: 32),
              const Text('Waiting for teacher to start the class', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    _infoRow(Icons.person_outline, c.teacherName),
                    _infoRow(Icons.menu_book_outlined, c.subjectName),
                    if (c.lessonTitle.isNotEmpty) _infoRow(Icons.play_lesson_outlined, c.lessonTitle),
                    _infoRow(Icons.event_outlined, '${c.classDate} \u2022 ${c.shortStartTime}-${c.shortEndTime}'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.purple.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                      child: Text(_countdownText(), style: const TextStyle(color: AppColors.purpleLight, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text("You'll join automatically the moment class starts.", style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Leave Waiting Room'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 14),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        ],
      ),
    );
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/liveclass/waiting_room_screen.dart"), $content_lib_screens_liveclass_waiting_room_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/liveclass/waiting_room_screen.dart" -ForegroundColor Green

# --- lib/screens/lessons/lesson_player_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/lessons") | Out-Null
$content_lib_screens_lessons_lesson_player_screen_dart = @'
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/lesson_model.dart';
import '../../providers/lesson_provider.dart';
import '../../services/lesson_service.dart';
import '../../widgets/notes_widget.dart';
import '../../widgets/skeleton_box.dart';
import '../lesson_videos_screen.dart';

/// Full lesson player: optional video, AI-generated explanation/key
/// points/examples/practice questions/summary, a Quiz button, recommended
/// YouTube videos, PDF notes, Previous/Next navigation, and Mark Complete.
///
/// If a lesson has no video, this screen shows the lesson's educational
/// thumbnail with "Educational content available — read notes below"
/// instead of an error, per the "no placeholder video" content strategy.
class LessonPlayerScreen extends StatefulWidget {
  final int lessonId;

  const LessonPlayerScreen({super.key, required this.lessonId});

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  final LessonService _lessonService = LessonService();

  LessonModel? _lesson;
  bool _isLoading = true;
  String? _errorMessage;

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _videoInitFailed = false;

  @override
  void initState() {
    super.initState();
    _loadLesson(widget.lessonId);
  }

  Future<void> _loadLesson(int lessonId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _disposeVideo();

    try {
      final lesson = await _lessonService.fetchLessonById(lessonId);
      // QA fix ("Missing mounted checks after async operations"): this
      // setState ran unconditionally right after an await - if the user
      // had already navigated away while the fetch was in flight, this
      // threw "setState() called after dispose()".
      if (!mounted) return;
      setState(() => _lesson = lesson);

      if (lesson.videoUrl.isNotEmpty && lesson.videoSource != 'youtube') {
        await _initVideo(ApiConstants.resolveMediaUrl(lesson.videoUrl));
      }

      // QA fix ("Missing mounted checks after async operations"): two
      // separate awaits sit inside this single mounted-guard - if the
      // widget got unmounted during loadNotes() (between the two
      // calls), loadAiContent() below would still run against a
      // disposed context. Re-checking mounted between them closes that
      // gap instead of only checking once at the top.
      if (mounted) {
        await context.read<LessonProvider>().loadNotes(lessonId);
        if (mounted) {
          await context.read<LessonProvider>().loadAiContent(lessonId);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Could not load this lesson. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initVideo(String url) async {
    _videoInitFailed = false;
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) {
        // BUG FIX (controller leak): dispose() has already run (and
        // won't run again) if we got here after the widget was
        // disposed - storing this controller in the fields now would
        // leak it forever. Dispose it directly instead.
        await controller.dispose();
        return;
      }
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
        errorBuilder: (context, errorMessage) => Center(
          child: Text(errorMessage, style: const TextStyle(color: Colors.white)),
        ),
      );
      _videoController = controller;
      setState(() {});
    } catch (e) {
      _videoController = null;
      _chewieController = null;
      if (mounted) setState(() => _videoInitFailed = true);
    }
  }

  void _disposeVideo() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
    _videoInitFailed = false;
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  void _goToLesson(LessonModel? target) {
    if (target == null) return;
    _loadLesson(target.id);
  }

  @override
  Widget build(BuildContext context) {
    final lessonProvider = context.watch<LessonProvider>();
    final previous = _lesson != null ? lessonProvider.previousOf(_lesson!.id) : null;
    final next = _lesson != null ? lessonProvider.nextOf(_lesson!.id) : null;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(_lesson?.title ?? 'Lesson')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: () => _loadLesson(widget.lessonId), child: const Text('Retry')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: _buildMediaArea(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLessonHeaderCard(),
                            const SizedBox(height: 16),
                            _buildNavigationRow(previous, next),
                            const SizedBox(height: 12),
                            _buildMarkCompleteButton(),
                            const SizedBox(height: 24),
                            _buildAiContentSection(lessonProvider),
                            const SizedBox(height: 24),
                            _buildVideosSection(),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: AppTheme.softShadow,
                              ),
                              child: NotesWidget(
                                notes: lessonProvider.notes,
                                isLoading: lessonProvider.isLoadingNotes,
                                errorMessage: lessonProvider.notesErrorMessage,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Recommended Videos — sits between AI Explanation and PDF Notes.
  /// Does not touch AI content, notes, progress, or the video player above.
  Widget _buildVideosSection() {
    if (_lesson == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: LessonVideosScreen(
        lessonId: _lesson!.id,
        lessonTitle: _lesson!.title,
      ),
    );
  }

  Widget _buildLessonHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_lesson!.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time_rounded, size: 14, color: AppColors.purple),
                const SizedBox(width: 6),
                Text('${_lesson!.duration} minutes', style: const TextStyle(color: AppColors.purple, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (_lesson!.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            Text(_lesson!.description, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _buildNavigationRow(LessonModel? previous, LessonModel? next) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: previous != null ? () => _goToLesson(previous) : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.skip_previous_rounded),
            label: const Text('Previous'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: next != null ? () => _goToLesson(next) : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Next'),
          ),
        ),
      ],
    );
  }

  Widget _buildMarkCompleteButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          await context.read<LessonProvider>().markCompleted(_lesson!.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lesson marked as complete')),
            );
          }
        },
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          foregroundColor: AppColors.green,
          side: const BorderSide(color: AppColors.green),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.check_circle_outline_rounded),
        label: const Text('Mark Complete'),
      ),
    );
  }

  Widget _buildAiContentSection(LessonProvider provider) {
    if (provider.isLoadingAiContent) {
      return Column(
        children: [
          SkeletonBox(height: 24, width: 160, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 12),
          SkeletonBox(height: 100, borderRadius: BorderRadius.circular(16)),
        ],
      );
    }

    if (provider.aiContentUnavailable) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.softShadow,
        ),
        child: const Text(
          'AI-generated notes for this lesson are not available yet. Check the PDF notes below.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    if (provider.aiContentErrorMessage != null) {
      return Text(provider.aiContentErrorMessage!, style: const TextStyle(color: AppColors.error));
    }

    final content = provider.aiContent;
    if (content == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _aiCard('Explanation', Icons.lightbulb_outline_rounded, Text(content.explanation, style: const TextStyle(height: 1.5))),
        const SizedBox(height: 14),
        if (content.keyPoints.isNotEmpty)
          _aiCard(
            'Key Points',
            Icons.checklist_rounded,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.keyPoints.map((p) => _bullet(p)).toList(),
            ),
          ),
        const SizedBox(height: 14),
        if (content.examples.isNotEmpty)
          _aiCard(
            'Examples',
            Icons.school_outlined,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.examples.map((p) => _bullet(p)).toList(),
            ),
          ),
        const SizedBox(height: 14),
        if (content.practiceQuestions.isNotEmpty)
          _aiCard(
            'Practice Questions',
            Icons.edit_note_rounded,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.practiceQuestions.map((p) => _bullet(p)).toList(),
            ),
          ),
        const SizedBox(height: 14),
        _aiCard('Summary', Icons.summarize_outlined, Text(content.summary, style: const TextStyle(height: 1.5))),
        if (content.quiz.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/quiz', extra: {'lessonId': _lesson!.id, 'questions': content.quiz}),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.quiz_rounded),
              label: const Text('Take Quiz'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _aiCard(String title, IconData icon, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.purple),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildMediaArea() {
    if (_lesson != null && _lesson!.videoUrl.isNotEmpty && _lesson!.videoSource == 'youtube') {
      final thumb = _lesson?.thumbnailUrl ?? '';
      return GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(_lesson!.videoUrl);
          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: Container(
          height: 220,
          color: Colors.black12,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb.isNotEmpty)
                Image.network(
                  ApiConstants.resolveMediaUrl(thumb),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              Container(
                color: Colors.black.withOpacity(0.35),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 56),
                    SizedBox(height: 8),
                    Text('Watch on YouTube', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_lesson == null || _lesson!.videoUrl.isEmpty) {
      // No placeholder/cartoon video — show the lesson's educational
      // thumbnail (if any) with a message pointing to the notes below.
      final thumb = _lesson?.thumbnailUrl ?? '';
      return Container(
        height: 220,
        color: Colors.black12,
        child: thumb.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    ApiConstants.resolveMediaUrl(thumb),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                  Container(
                    color: Colors.black.withOpacity(0.35),
                    alignment: Alignment.center,
                    child: const Text(
                      'Educational content available\nRead notes below',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              )
            : const Center(
                child: Text(
                  'Educational content available\nRead notes below',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
      );
    }

    if (_videoInitFailed) {
      return Container(
        height: 220,
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 36),
              const SizedBox(height: 8),
              const Text('Could not load this video.', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                onPressed: () => _initVideo(ApiConstants.resolveMediaUrl(_lesson!.videoUrl)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_chewieController == null) {
      return Container(
        height: 220,
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return AspectRatio(
      aspectRatio: _chewieController!.aspectRatio ?? 16 / 9,
      child: Chewie(controller: _chewieController!),
    );
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/lessons/lesson_player_screen.dart"), $content_lib_screens_lessons_lesson_player_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/lessons/lesson_player_screen.dart" -ForegroundColor Green

# --- lib/screens/liveclass/resource_video_viewer_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/liveclass") | Out-Null
$content_lib_screens_liveclass_resource_video_viewer_screen_dart = @'
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// In-app video player for Class Resources - reuses the same
/// video_player + chewie stack as lesson playback elsewhere in the app.
class ResourceVideoViewerScreen extends StatefulWidget {
  final String url;
  final String fileName;

  const ResourceVideoViewerScreen({super.key, required this.url, required this.fileName});

  @override
  State<ResourceVideoViewerScreen> createState() => _ResourceVideoViewerScreenState();
}

class _ResourceVideoViewerScreenState extends State<ResourceVideoViewerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      if (!mounted) {
        // BUG FIX (controller leak): dispose() already ran if we're
        // here unmounted, and won't run again - dispose this orphaned
        // controller directly instead of leaking it.
        await controller.dispose();
        return;
      }
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
        errorBuilder: (context, errorMessage) => Center(
          child: Text(errorMessage, style: const TextStyle(color: Colors.white)),
        ),
      );
      _videoController = controller;
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: _hasError
            ? const Text('Could not load this video.', style: TextStyle(color: Colors.white70))
            : (_chewieController != null
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Colors.white54)),
      ),
    );
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/liveclass/resource_video_viewer_screen.dart"), $content_lib_screens_liveclass_resource_video_viewer_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/liveclass/resource_video_viewer_screen.dart" -ForegroundColor Green

# --- lib/screens/liveclass/create_live_class_screen.dart ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "lib/screens/liveclass") | Out-Null
$content_lib_screens_liveclass_create_live_class_screen_dart = @'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subject_model.dart';
import '../../services/live_class_service.dart';
import '../../services/subject_service.dart';

/// Teacher schedules a class - date/time/subject/capacity only. No
/// "Start Class" here since there's no video backend yet.
class CreateLiveClassScreen extends StatefulWidget {
  const CreateLiveClassScreen({super.key});

  @override
  State<CreateLiveClassScreen> createState() => _CreateLiveClassScreenState();
}

class _CreateLiveClassScreenState extends State<CreateLiveClassScreen> {
  final LiveClassService _service = LiveClassService();
  final SubjectService _subjectService = SubjectService();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxStudentsController = TextEditingController();

  List<SubjectModel> _subjects = [];
  int? _selectedSubjectId;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);
  bool _loadingSubjects = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      _subjects = await _subjectService.fetchAllSubjects();
    } catch (_) {}
    if (mounted) setState(() => _loadingSubjects = false);
  }

  String _fmtDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _schedule() async {
    if (_selectedSubjectId == null || _titleController.text.trim().isEmpty) {
      setState(() => _error = 'Subject and title are required.');
      return;
    }

    final maxStudents = int.tryParse(_maxStudentsController.text.trim());
    if (maxStudents == null || maxStudents < 1) {
      setState(() => _error = 'Maximum Students is required and must be a valid number.');
      return;
    }

    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    if (endMinutes <= startMinutes) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.create(
        subjectId: _selectedSubjectId!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        classDate: _fmtDate(_date),
        startTime: _fmtTime(_startTime),
        endTime: _fmtTime(_endTime),
        maxStudents: maxStudents,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Class scheduled.')));
        context.pop();
      }
    } catch (e) {
      setState(() => _error = 'Failed to schedule class. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _maxStudentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Schedule Live Class')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(
            title: 'Subject',
            child: _loadingSubjects
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<int?>(
                    value: _selectedSubjectId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Select a subject'),
                    items: _subjects.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))).toList(),
                    onChanged: (v) => setState(() => _selectedSubjectId = v),
                  ),
          ),
          const SizedBox(height: 14),
          _card(title: 'Title', child: TextField(controller: _titleController, decoration: const InputDecoration(border: OutlineInputBorder()))),
          const SizedBox(height: 14),
          _card(title: 'Description', child: TextField(controller: _descriptionController, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder()))),
          const SizedBox(height: 14),
          _card(
            title: 'Date',
            child: Row(
              children: [
                Expanded(child: Text(_fmtDate(_date))),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (picked != null && mounted) setState(() => _date = picked);
                  },
                  child: const Text('Pick date'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _card(
                  title: 'Start Time',
                  child: Row(
                    children: [
                      Expanded(child: Text(_startTime.format(context))),
                      TextButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: _startTime);
                          if (picked != null && mounted) setState(() => _startTime = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _card(
                  title: 'End Time',
                  child: Row(
                    children: [
                      Expanded(child: Text(_endTime.format(context))),
                      TextButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: _endTime);
                          if (picked != null && mounted) setState(() => _endTime = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Maximum Students *',
            child: TextField(
              controller: _maxStudentsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Required'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _schedule,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppColors.purple),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Schedule Class'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "lib/screens/liveclass/create_live_class_screen.dart"), $content_lib_screens_liveclass_create_live_class_screen_dart, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote lib/screens/liveclass/create_live_class_screen.dart" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Run: flutter analyze" -ForegroundColor Yellow