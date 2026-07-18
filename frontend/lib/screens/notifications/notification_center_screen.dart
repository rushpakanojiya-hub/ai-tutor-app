import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../../widgets/skeleton_box.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final NotificationService _service = NotificationService();
  List<NotificationModel> _notifications = [];
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
      _notifications = await _service.fetchAll();
    } catch (e) {
      _error = 'Could not load notifications.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'live_class_cancelled':
        return Icons.event_busy_rounded;
      case 'new_live_class':
        return Icons.video_camera_front_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await _service.markAllRead();
              if (!mounted) return;
              _load();
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: List.generate(4, (_) => const Padding(padding: EdgeInsets.all(12), child: SkeletonBox(height: 70, borderRadius: BorderRadius.all(Radius.circular(14))))))
            : _error != null
                ? ListView(children: [const SizedBox(height: 80), Center(child: Text(_error!))])
                : _notifications.isEmpty
                    ? ListView(children: const [SizedBox(height: 100), Center(child: Text('No notifications yet.', style: TextStyle(color: AppColors.textSecondary)))])
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final n = _notifications[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: n.isRead ? AppColors.card : AppColors.purpleLight,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: AppTheme.softShadow,
                            ),
                            child: InkWell(
                              onTap: () async {
                                if (!n.isRead) {
                                  await _service.markRead(n.id);
                                  if (!mounted) return;
                                  _load();
                                }
                              },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(_iconFor(n.type), color: AppColors.purple, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Text(n.body, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  if (!n.isRead)
                                    Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4), decoration: const BoxDecoration(color: AppColors.purple, shape: BoxShape.circle)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
