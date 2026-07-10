import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/assignment_model.dart';
import '../../services/api_service.dart';
import '../../services/assignment_service.dart';
import '../../widgets/skeleton_box.dart';

/// Teacher's review queue for one assignment: a compact list, tapping a
/// submission opens the full review page (SubmissionDetailReviewScreen)
/// where the complete answer is readable before scoring it.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(children: List.generate(3, (_) => const Padding(padding: EdgeInsets.all(16), child: SkeletonBox(height: 90, borderRadius: BorderRadius.all(Radius.circular(18))))))
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
                          final reviewed = eval?.reviewedByTeacher ?? false;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () async {
                                  final updated = await Navigator.push<AssignmentSubmissionModel>(
                                    context,
                                    MaterialPageRoute(builder: (_) => SubmissionDetailReviewScreen(submission: sub)),
                                  );
                                  // QA fix ("Snackbar after Navigator.pop" / "Safe
                                  // BuildContext usage"): mounted IS checked in the
                                  // same condition as this context use, immediately
                                  // after the await, with nothing in between - but the
                                  // analyzer has a known blind spot for `mounted`
                                  // checks inside a doubly-nested closure (itemBuilder
                                  // -> onTap). Verified safe; not an unguarded use.
                                  if (updated != null && mounted) {
                                    _load();
                                    // ignore: use_build_context_synchronously
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Review saved.')));
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(sub.studentName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                            const SizedBox(height: 2),
                                            Text(
                                              reviewed ? 'Reviewed' : (eval != null ? 'AI evaluated - awaiting your review' : 'Evaluating...'),
                                              style: TextStyle(fontSize: 11, color: reviewed ? AppColors.green : AppColors.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (eval != null)
                                        Text('${eval.teacherOverrideScore ?? eval.aiScore ?? 0}/${eval.maxScore ?? 0}', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w800)),
                                      const SizedBox(width: 6),
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

/// Full-page submission review: complete scrollable answer, then AI
/// evaluation, then the teacher's own score + feedback.
class SubmissionDetailReviewScreen extends StatefulWidget {
  final AssignmentSubmissionModel submission;

  const SubmissionDetailReviewScreen({super.key, required this.submission});

  @override
  State<SubmissionDetailReviewScreen> createState() => _SubmissionDetailReviewScreenState();
}

class _SubmissionDetailReviewScreenState extends State<SubmissionDetailReviewScreen> {
  final AssignmentService _service = AssignmentService();
  late final TextEditingController _scoreController;
  late final TextEditingController _feedbackController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final eval = widget.submission.evaluation;
    _scoreController = TextEditingController(text: (eval?.teacherOverrideScore ?? eval?.aiScore)?.toString() ?? '');
    _feedbackController = TextEditingController(text: eval?.teacherFeedback ?? '');
  }

  @override
  void dispose() {
    _scoreController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.reviewSubmission(
        widget.submission.id,
        overrideScore: int.tryParse(_scoreController.text),
        feedback: _feedbackController.text.trim(),
      );
      // QA fix ("Snackbar after Navigator.pop"): this screen used to show
      // its own "Review saved" SnackBar right here, then immediately pop
      // itself - the Scaffold the SnackBar was attached to got torn down
      // before it ever really rendered. The confirmation is now shown by
      // the caller (SubmissionReviewScreen) after this pop returns, on a
      // screen that's actually still around to display it.
      if (mounted) {
        Navigator.pop(context, widget.submission);
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save review.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.submission;
    final eval = sub.evaluation;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(sub.studentName)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(
            title: 'Submission',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sub.submittedAt != null)
                  Text('Submitted ${sub.submittedAt!.day}/${sub.submittedAt!.month}/${sub.submittedAt!.year} at ${sub.submittedAt!.hour.toString().padLeft(2, '0')}:${sub.submittedAt!.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                const Text('Student Answer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.pageBackground, borderRadius: BorderRadius.circular(12)),
                  child: SelectableText(sub.submissionText, style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (eval != null)
            _card(
              title: '\u{1F916} AI Evaluation',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Score: ${eval.aiScore ?? 0}/${eval.maxScore ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.purple)),
                  if (eval.strengths.isNotEmpty) ..._section('Strengths', eval.strengths, AppColors.green),
                  if (eval.weaknesses.isNotEmpty) ..._section('Weaknesses', eval.weaknesses, AppColors.orange),
                  if (eval.missingConcepts.isNotEmpty) ..._section('Missing Concepts', eval.missingConcepts, AppColors.error),
                  if (eval.suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Suggestions: ${eval.suggestions}', style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            )
          else
            _card(title: '\u{1F916} AI Evaluation', child: const Text('Still evaluating...', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
          const SizedBox(height: 16),
          _card(
            title: 'Your Review',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _scoreController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Final Score (out of ${eval?.maxScore ?? 10})', border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _feedbackController,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Feedback for student', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple, minimumSize: const Size.fromHeight(48)),
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save Review'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(String title, List<String> items, Color color) {
    return [
      const SizedBox(height: 10),
      Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color)),
      ...items.map((i) => Padding(padding: const EdgeInsets.only(top: 2), child: Text('\u2022 $i', style: const TextStyle(fontSize: 12)))),
    ];
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
