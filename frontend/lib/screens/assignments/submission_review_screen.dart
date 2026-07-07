import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/assignment_model.dart';
import '../../services/assignment_service.dart';
import '../../widgets/skeleton_box.dart';

/// Teacher's review queue for one assignment: sees each student's
/// submission plus the AI evaluation, and can optionally override the
/// score and add written feedback (fully optional per the spec).
class SubmissionReviewScreen extends StatefulWidget {
  final int assignmentId;
  final String title;

  const SubmissionReviewScreen({super.key, required this.assignmentId, required this.title});

  @override
  State<SubmissionReviewScreen> createState() => _SubmissionReviewScreenState();
}

class _SubmissionReviewScreenState extends State<SubmissionReviewScreen> {
  final AssignmentService _service = AssignmentService();

  List<AssignmentSubmissionModel> _submissions = [];
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
      _submissions = await _service.fetchSubmissions(widget.assignmentId);
    } catch (e) {
      _error = 'Could not load submissions.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _openReview(AssignmentSubmissionModel sub) async {
    final scoreController = TextEditingController(text: sub.evaluation?.teacherOverrideScore?.toString() ?? sub.evaluation?.aiScore?.toString() ?? '');
    final feedbackController = TextEditingController(text: sub.evaluation?.teacherFeedback ?? '');

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Review: ${sub.studentName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: scoreController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Score (out of ${sub.evaluation?.maxScore ?? 10})', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feedbackController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Feedback for student', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
                child: const Text('Save Review'),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        await _service.reviewSubmission(
          sub.id,
          overrideScore: int.tryParse(scoreController.text),
          feedback: feedbackController.text.trim(),
        );
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save review.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: List.generate(3, (_) => const Padding(padding: EdgeInsets.all(16), child: SkeletonBox(height: 100, borderRadius: BorderRadius.all(Radius.circular(18))))))
            : _error != null
                ? ListView(children: [const SizedBox(height: 80), Center(child: Text(_error!))])
                : _submissions.isEmpty
                    ? ListView(children: const [SizedBox(height: 100), Center(child: Text('No submissions yet.', style: TextStyle(color: AppColors.textSecondary)))])
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _submissions.length,
                        itemBuilder: (context, index) {
                          final sub = _submissions[index];
                          final eval = sub.evaluation;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(sub.studentName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                                    if (eval != null)
                                      Text('${eval.teacherOverrideScore ?? eval.aiScore ?? 0}/${eval.maxScore ?? 0}', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(sub.submissionText, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                if (eval != null && eval.reviewedByTeacher) ...[
                                  const SizedBox(height: 8),
                                  const Text('Reviewed', style: TextStyle(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w600)),
                                ],
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(onPressed: () => _openReview(sub), child: const Text('View & Review')),
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
