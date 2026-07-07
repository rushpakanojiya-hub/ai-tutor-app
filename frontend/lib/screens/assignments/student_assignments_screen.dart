import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/assignment_model.dart';
import '../../services/assignment_service.dart';
import '../../widgets/skeleton_box.dart';

/// Dedicated Assignments tab - every published assignment across every
/// subject the student is enrolled in, in one place (no more digging
/// through Course -> Subject -> Lesson to find one).
class StudentAssignmentsScreen extends StatefulWidget {
  const StudentAssignmentsScreen({super.key});

  @override
  State<StudentAssignmentsScreen> createState() => _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState extends State<StudentAssignmentsScreen> {
  final AssignmentService _service = AssignmentService();

  List<AssignmentModel> _assignments = [];
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
      _assignments = await _service.fetchForStudent();
    } catch (e) {
      _error = 'Could not load your assignments.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  ({String label, Color color}) _statusInfo(String myStatus) {
    switch (myStatus) {
      case 'submitted':
      case 'under_review':
        return (label: 'Submitted', color: AppColors.blue);
      case 'evaluated':
        return (label: 'Evaluated', color: AppColors.green);
      case 'returned':
        return (label: 'Reviewed', color: AppColors.purple);
      default:
        return (label: 'Pending', color: AppColors.orange);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Assignments'), automaticallyImplyLeading: false),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: List.generate(3, (_) => const Padding(padding: EdgeInsets.all(16), child: SkeletonBox(height: 100, borderRadius: BorderRadius.all(Radius.circular(18))))))
            : _error != null
                ? ListView(children: [const SizedBox(height: 80), Center(child: Text(_error!)), Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry')))])
                : _assignments.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 100),
                        Icon(Icons.assignment_turned_in_outlined, size: 48, color: AppColors.textSecondary),
                        SizedBox(height: 12),
                        Center(child: Text('No assignments yet.', style: TextStyle(color: AppColors.textSecondary))),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _assignments.length,
                        itemBuilder: (context, index) {
                          final a = _assignments[index];
                          final status = _statusInfo(a.myStatus);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => context.push('/assignment-detail', extra: {'assignmentId': a.id}),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(color: status.color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                                            child: Text(status.label, style: TextStyle(color: status.color, fontSize: 10, fontWeight: FontWeight.w700)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text('${a.subjectName} \u2022 ${a.teacherName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 4,
                                        children: [
                                          _miniInfo(Icons.grade_outlined, '${a.maxMarks} marks'),
                                          _miniInfo(Icons.speed_outlined, a.difficulty),
                                          if (a.estimatedMinutes != null) _miniInfo(Icons.timer_outlined, '${a.estimatedMinutes} min'),
                                          if (a.dueDate != null) _miniInfo(Icons.event_outlined, 'Due ${a.dueDate!.day}/${a.dueDate!.month}/${a.dueDate!.year}'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
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
}
