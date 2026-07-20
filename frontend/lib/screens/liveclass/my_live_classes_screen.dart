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
