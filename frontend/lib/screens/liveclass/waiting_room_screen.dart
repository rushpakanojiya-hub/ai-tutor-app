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
                    _infoRow(Icons.event_outlined, '${c.classDate} \u2022 ${c.startTime.substring(0, 5)}-${c.endTime.substring(0, 5)}'),
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
