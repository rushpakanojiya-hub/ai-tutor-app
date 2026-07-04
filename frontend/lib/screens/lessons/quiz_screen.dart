import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ai_content_model.dart';
import '../../providers/lesson_provider.dart';

/// A simple multiple-choice quiz for a lesson's AI-generated quiz
/// questions. On finishing, the score (0-100) is saved via
/// LessonProvider.markCompleted(lessonId, score: ...), which also marks
/// the lesson complete.
class QuizScreen extends StatefulWidget {
  final int lessonId;
  final List<QuizQuestionModel> questions;

  const QuizScreen({super.key, required this.lessonId, required this.questions});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late List<int?> _selected;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _selected = List<int?>.filled(widget.questions.length, null);
  }

  int get _correctCount {
    int count = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      if (_selected[i] == widget.questions[i].correctOption) count++;
    }
    return count;
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    final scorePercent = ((_correctCount / widget.questions.length) * 100).round();
    await context.read<LessonProvider>().markCompleted(widget.lessonId, score: scorePercent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_submitted) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.greenLight,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: AppColors.green, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'You scored ${_correctCount} / ${widget.questions.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          for (var i = 0; i < widget.questions.length; i++) _buildQuestion(i),
          const SizedBox(height: 12),
          if (!_submitted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected.every((s) => s != null) ? _submit : null,
                child: const Text('Submit Quiz'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('Back to Lesson'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestion(int index) {
    final q = widget.questions[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Q${index + 1}. ${q.question}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 10),
          for (var j = 0; j < q.options.length; j++) _buildOption(index, j, q),
        ],
      ),
    );
  }

  Widget _buildOption(int qIndex, int optionIndex, QuizQuestionModel q) {
    final selected = _selected[qIndex] == optionIndex;
    Color bg = AppColors.pageBackground;
    Color fg = AppColors.textPrimary;

    if (_submitted) {
      if (optionIndex == q.correctOption) {
        bg = AppColors.greenLight;
        fg = AppColors.green;
      } else if (selected) {
        bg = const Color(0xFFFFE5E5);
        fg = AppColors.error;
      }
    } else if (selected) {
      bg = AppColors.purpleLight;
      fg = AppColors.purple;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: _submitted
            ? null
            : () => setState(() => _selected[qIndex] = optionIndex),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(q.options[optionIndex], style: TextStyle(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ),
      ),
    );
  }
}
