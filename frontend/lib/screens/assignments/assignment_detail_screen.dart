import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/assignment_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/assignment_service.dart';

/// Student's assignment detail: read instructions, write/save a draft,
/// submit, and see the real AI evaluation once it's submitted.
class AssignmentDetailScreen extends StatefulWidget {
  final int assignmentId;

  const AssignmentDetailScreen({super.key, required this.assignmentId});

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  final AssignmentService _service = AssignmentService();
  final _answerController = TextEditingController();

  AssignmentModel? _assignment;
  AssignmentSubmissionModel? _submission;
  bool _isLoading = true;
  bool _saving = false;
  bool _retryingEvaluation = false;
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
      _assignment = await _service.fetchById(widget.assignmentId);
      _submission = await _service.fetchMySubmission(widget.assignmentId);
      if (_submission != null) _answerController.text = _submission!.submissionText;
    } catch (e) {
      _error = 'Could not load this assignment.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool get _isSubmitted => _submission != null && _submission!.status != 'draft';

  Future<void> _saveDraft() async {
    setState(() => _saving = true);
    try {
      await _service.saveDraft(widget.assignmentId, _answerController.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draft saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save draft.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    if (_answerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please write an answer before submitting.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit assignment?'),
        content: const Text("You won't be able to edit your answer after submitting."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      _submission = await _service.submit(widget.assignmentId, _answerController.text.trim());
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to submit. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _retryEvaluation() async {
    if (_submission == null) return;
    setState(() => _retryingEvaluation = true);
    try {
      _submission = await _service.retryEvaluation(_submission!.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Still could not evaluate. Please try again in a moment.')),
        );
      }
    } finally {
      if (mounted) setState(() => _retryingEvaluation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().currentUser?.role;
    if (role != 'student') {
      return Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: AppBar(title: const Text('Assignment')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('This view is for students. Use "Review Submissions" to see student answers.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(_assignment?.title ?? 'Assignment')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final a = _assignment!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                _tag('${a.maxMarks} marks', AppColors.purpleLight, AppColors.purple),
                _tag(a.difficulty, AppColors.orangeLight, AppColors.orange),
                if (a.estimatedMinutes != null) _tag('${a.estimatedMinutes} min', AppColors.blueLight, AppColors.blue),
              ]),
              if (a.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(a.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
              if (a.instructions.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Instructions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(a.instructions, style: const TextStyle(fontSize: 13, height: 1.4)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your Answer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: _answerController,
                maxLines: 8,
                enabled: !_isSubmitted,
                decoration: InputDecoration(
                  hintText: 'Write your answer here...',
                  filled: true,
                  fillColor: AppColors.pageBackground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              if (!_isSubmitted) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: _saving ? null : _saveDraft, child: const Text('Save Draft'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
                        child: _saving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Submit'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_isSubmitted) ...[
          const SizedBox(height: 16),
          _buildEvaluationCard(),
        ],
      ],
    );
  }

  Widget _buildEvaluationCard() {
    final eval = _submission?.evaluation;
    if (eval == null) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.hourglass_empty_rounded, color: AppColors.orange, size: 18),
                SizedBox(width: 10),
                Expanded(child: Text("Evaluation hasn't come through yet.", style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _retryingEvaluation ? null : _retryEvaluation,
                icon: _retryingEvaluation
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(_retryingEvaluation ? 'Retrying...' : 'Retry Evaluation'),
              ),
            ),
          ],
        ),
      );
    }

    final aiScore = eval.aiScore ?? 0;
    final hasTeacherScore = eval.reviewedByTeacher && eval.teacherOverrideScore != null;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('\u{1F916} AI Evaluation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              Text('AI: $aiScore/${eval.maxScore ?? 0}', style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          if (hasTeacherScore) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.verified_rounded, size: 14, color: AppColors.green),
                const SizedBox(width: 6),
                Text('Teacher Score: ${eval.teacherOverrideScore}/${eval.maxScore ?? 0}', style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w800, fontSize: 14)),
              ],
            ),
          ],
          if (eval.strengths.isNotEmpty) ..._section('Strengths', eval.strengths, AppColors.green),
          if (eval.weaknesses.isNotEmpty) ..._section('Areas to improve', eval.weaknesses, AppColors.orange),
          if (eval.missingConcepts.isNotEmpty) ..._section('Missing concepts', eval.missingConcepts, AppColors.error),
          if (eval.suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Suggestions: ${eval.suggestions}', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          ],
          if (eval.teacherFeedback.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(10)),
              child: Text('Teacher feedback: ${eval.teacherFeedback}', style: const TextStyle(fontSize: 12, color: AppColors.purple)),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _section(String title, List<String> items, Color color) {
    return [
      const SizedBox(height: 10),
      Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color)),
      ...items.map((i) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('\u2022 $i', style: const TextStyle(fontSize: 12)),
          )),
    ];
  }

  Widget _tag(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
      child: child,
    );
  }
}
