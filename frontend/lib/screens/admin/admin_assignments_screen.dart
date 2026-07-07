import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/assignment_model.dart';
import '../../services/assignment_service.dart';
import '../../widgets/skeleton_box.dart';

/// Admin's platform-wide assignment monitoring: real counts + full list.
/// Admin never evaluates or creates assignments - view-only.
class AdminAssignmentsScreen extends StatefulWidget {
  const AdminAssignmentsScreen({super.key});

  @override
  State<AdminAssignmentsScreen> createState() => _AdminAssignmentsScreenState();
}

class _AdminAssignmentsScreenState extends State<AdminAssignmentsScreen> {
  final AssignmentService _service = AssignmentService();

  List<AssignmentModel> _assignments = [];
  AssignmentAnalyticsModel? _analytics;
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
      _assignments = await _service.fetchAllForAdmin();
      _analytics = await _service.fetchAdminAnalytics();
    } catch (e) {
      _error = 'Could not load assignments.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Assignments Monitoring')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: const [SkeletonBox(height: 100, borderRadius: BorderRadius.all(Radius.circular(18)))])
            : _error != null
                ? ListView(children: [const SizedBox(height: 80), Center(child: Text(_error!))])
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (_analytics != null) _buildAnalytics(_analytics!),
                      const SizedBox(height: 20),
                      const Text('All Assignments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 10),
                      ..._assignments.map((a) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
                                      child: Text(a.status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.purple)),
                                    ),
                                  ],
                                ),
                                if (a.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(a.description, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    _miniInfo(Icons.person_outline, a.teacherName),
                                    _miniInfo(Icons.menu_book_outlined, a.subjectName),
                                    _miniInfo(Icons.grade_outlined, '${a.maxMarks} marks'),
                                    _miniInfo(Icons.speed_outlined, a.difficulty),
                                    if (a.dueDate != null) _miniInfo(Icons.event_outlined, 'Due ${a.dueDate!.day}/${a.dueDate!.month}/${a.dueDate!.year}'),
                                    _miniInfo(Icons.event_available_outlined, 'Created ${a.createdAt.day}/${a.createdAt.month}/${a.createdAt.year}'),
                                    _miniInfo(Icons.people_outline, '${a.submissionCount} submission${a.submissionCount == 1 ? '' : 's'}'),
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

  Widget _buildAnalytics(AssignmentAnalyticsModel a) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _stat('Total Assignments', '${a.totalAssignments}', AppColors.purple, AppColors.purpleLight),
        _stat('Published', '${a.publishedAssignments}', AppColors.green, AppColors.greenLight),
        _stat('Submissions', '${a.totalSubmissions}', AppColors.blue, AppColors.blueLight),
        _stat('Avg Score', '${a.averageScorePercent.toStringAsFixed(0)}%', AppColors.orange, AppColors.orangeLight),
      ],
    );
  }

  Widget _miniInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _stat(String label, String value, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
