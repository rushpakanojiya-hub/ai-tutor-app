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
                            Text('${c.classDate} \u2022 ${c.startTime.substring(0, 5)}-${c.endTime.substring(0, 5)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
