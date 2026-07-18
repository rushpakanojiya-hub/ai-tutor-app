import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/assignment_model.dart';
import '../../services/api_service.dart';
import '../../services/assignment_service.dart';
import '../../widgets/skeleton_box.dart';

/// Teacher's own assignments: create, edit status (publish/unpublish/
/// archive), delete, and jump into the submission review queue.
class MyAssignmentsScreen extends StatefulWidget {
  const MyAssignmentsScreen({super.key});

  @override
  State<MyAssignmentsScreen> createState() => _MyAssignmentsScreenState();
}

class _MyAssignmentsScreenState extends State<MyAssignmentsScreen> {
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
      _assignments = await _service.fetchMine();
    } catch (e) {
      _error = 'Could not load your assignments.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _setStatus(AssignmentModel a, Future<void> Function(int) action) async {
    try {
      await action(a.id);
      if (!mounted) return;
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action failed. Please try again.')));
    }
  }

  Future<void> _delete(AssignmentModel a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete assignment?'),
        content: Text('"${a.title}" and any submissions will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await _setStatus(a, _service.delete);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'published':
        return AppColors.green;
      case 'closed':
        return AppColors.blue;
      case 'archived':
        return AppColors.textSecondary;
      default:
        return AppColors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('My Assignments')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.purple,
        onPressed: () async {
          await context.push('/create-assignment');
          if (!mounted) return;
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
                : _assignments.isEmpty
                    ? ListView(children: const [SizedBox(height: 100), Center(child: Text('No assignments yet. Tap + to create one.', style: TextStyle(color: AppColors.textSecondary)))])
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _assignments.length,
                        itemBuilder: (context, index) {
                          final a = _assignments[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: _statusColor(a.status).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                                      child: Text(a.status, style: TextStyle(color: _statusColor(a.status), fontSize: 10, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('${a.subjectName} \u2022 ${a.submissionCount} submission${a.submissionCount == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (a.status != 'published')
                                      OutlinedButton(onPressed: () => _setStatus(a, _service.publish), child: const Text('Publish')),
                                    if (a.status == 'published')
                                      OutlinedButton(onPressed: () => _setStatus(a, _service.unpublish), child: const Text('Unpublish')),
                                    if (a.status == 'published')
                                      OutlinedButton(onPressed: () => _setStatus(a, _service.close), child: const Text('Close')),
                                    OutlinedButton(
                                      onPressed: () => context.push('/assignment-submissions', extra: {'assignmentId': a.id, 'title': a.title}),
                                      child: const Text('Review Submissions'),
                                    ),
                                    OutlinedButton(onPressed: () => _setStatus(a, _service.archive), child: const Text('Archive')),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                                      onPressed: () => _delete(a),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
