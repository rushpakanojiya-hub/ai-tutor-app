import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/assignment_model.dart';
import '../../services/assignment_service.dart';
import '../../widgets/skeleton_box.dart';

/// Published assignments for one subject - what a student sees.
class AssignmentListScreen extends StatefulWidget {
  final int subjectId;
  final String subjectName;

  const AssignmentListScreen({super.key, required this.subjectId, required this.subjectName});

  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen> {
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
      _assignments = await _service.fetchForSubject(widget.subjectId);
    } catch (e) {
      _error = 'Could not load assignments.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text('${widget.subjectName} Assignments')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: List.generate(3, (_) => const Padding(padding: EdgeInsets.all(16), child: SkeletonBox(height: 90, borderRadius: BorderRadius.all(Radius.circular(18))))))
            : _error != null
                ? ListView(children: [const SizedBox(height: 80), Center(child: Text(_error!)), Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry')))])
                : _assignments.isEmpty
                    ? ListView(children: const [SizedBox(height: 100), Center(child: Text('No assignments yet for this subject.', style: TextStyle(color: AppColors.textSecondary)))])
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _assignments.length,
                        itemBuilder: (context, index) {
                          final a = _assignments[index];
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
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(color: AppColors.purple.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                                        child: const Icon(Icons.assignment_rounded, color: AppColors.purple),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                            const SizedBox(height: 2),
                                            Text(
                                              a.dueDate != null ? 'Due ${a.dueDate!.day}/${a.dueDate!.month}/${a.dueDate!.year} \u2022 ${a.maxMarks} marks' : '${a.maxMarks} marks',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
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
}
