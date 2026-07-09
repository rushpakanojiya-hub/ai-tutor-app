import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/live_class_model.dart';
import '../../services/live_class_service.dart';
import '../../widgets/skeleton_box.dart';
import 'live_class_room_screen.dart';
import 'waiting_room_screen.dart';

/// Student's class schedule - grouped into Upcoming / Past. Each upcoming
/// class shows a live countdown and a check-in button (self-attendance,
/// enabled only during the scheduled window). "Join" is an honest
/// placeholder - there's no video backend yet, so it explains that
/// instead of pretending to connect to a call.
class StudentLiveClassesScreen extends StatefulWidget {
  const StudentLiveClassesScreen({super.key});

  @override
  State<StudentLiveClassesScreen> createState() => _StudentLiveClassesScreenState();
}

class _StudentLiveClassesScreenState extends State<StudentLiveClassesScreen> {
  final LiveClassService _service = LiveClassService();
  List<LiveClassModel> _classes = [];
  AttendanceSummary? _summary;
  bool _isLoading = true;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _classes = await _service.fetchForStudent();
    } catch (e) {
      _error = 'Could not load classes.';
    }
    try {
      _summary = await _service.fetchAttendanceSummary();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
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

  String _countdownText(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return 'Starting now';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  bool _isWithinWindow(LiveClassModel c) {
    final dt = c.dateTime;
    if (dt == null) return false;
    final endParts = c.endTime.split(':').map(int.parse).toList();
    final end = DateTime(dt.year, dt.month, dt.day, endParts[0], endParts[1]);
    final now = DateTime.now();
    return now.isAfter(dt) && now.isBefore(end);
  }

  Future<void> _join(LiveClassModel c) async {
    if (c.meetingStatus != 'live') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => WaitingRoomScreen(liveClass: c)));
      _load();
      return;
    }
    try {
      final session = await _service.joinClass(c.id);
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
            isTeacher: false,
          ),
        ),
      );
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not join the class. Please try again.')));
    }
  }

  Future<void> _checkIn(LiveClassModel c) async {
    try {
      final status = await _service.checkIn(c.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status == 'late' ? "Checked in - marked as late." : "Checked in - you're present!")),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-in is only available during class time.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _classes.where((c) => c.status == 'scheduled').toList();
    final others = _classes.where((c) => c.status != 'scheduled').toList();

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Live Classes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: List.generate(3, (_) => const Padding(padding: EdgeInsets.all(16), child: SkeletonBox(height: 90, borderRadius: BorderRadius.all(Radius.circular(18))))))
            : _error != null
                ? ListView(children: [const SizedBox(height: 80), Center(child: Text(_error!))])
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (_summary != null) _buildAttendanceSummary(_summary!),
                      const SizedBox(height: 20),
                      if (upcoming.isNotEmpty) ...[
                        const Text('Upcoming', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 10),
                        ...upcoming.map(_buildUpcomingCard),
                        const SizedBox(height: 20),
                      ],
                      if (others.isNotEmpty) ...[
                        const Text('Past Classes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 10),
                        ...others.map(_buildPastCard),
                      ],
                      if (_classes.isEmpty) const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No classes scheduled yet.', style: TextStyle(color: AppColors.textSecondary)))),
                    ],
                  ),
      ),
    );
  }

  Widget _buildAttendanceSummary(AttendanceSummary s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.fact_check_rounded, color: AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.percentage.toStringAsFixed(0)}% Attendance', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text('${s.attendedCount}/${s.totalCompletedClasses} classes attended', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingCard(LiveClassModel c) {
    final dt = c.dateTime;
    final withinWindow = _isWithinWindow(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text('${c.subjectName} \u2022 ${c.teacherName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text('${c.classDate} \u2022 ${c.startTime.substring(0, 5)}-${c.endTime.substring(0, 5)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          if (dt != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
              child: Text(
                c.meetingStatus == 'live'
                    ? 'Live now'
                    : (withinWindow ? 'Starts in ${_countdownText(dt)}' : 'Starts in ${_countdownText(dt)}'),
                style: const TextStyle(color: AppColors.purple, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: withinWindow ? () => _checkIn(c) : null,
                  child: const Text("I'm Present"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: c.meetingStatus == 'live' ? AppColors.green : AppColors.purple),
                  onPressed: () => _join(c),
                  child: Text(c.meetingStatus == 'live' ? 'Join Now' : 'Join Class'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPastCard(LiveClassModel c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _statusColor(c.status).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  c.status == 'completed' ? 'Class Ended' : c.status[0].toUpperCase() + c.status.substring(1),
                  style: TextStyle(color: _statusColor(c.status), fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${c.subjectName} \u2022 ${c.teacherName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text('${c.classDate} \u2022 ${c.startTime.substring(0, 5)}-${c.endTime.substring(0, 5)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
