import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ai_content_model.dart';
import '../../models/quiz_attempt_model.dart';
import '../../providers/lesson_provider.dart';
import '../../services/quiz_service.dart';

/// A quiz screen with two modes:
///
/// - Lesson mode (lessonId set, [questions] a List<QuizQuestionModel>):
///   always single-correct MCQ, graded server-side against the lesson's
///   stored answer key. Unchanged from before.
/// - Freeform mode ([freeformQuestions] set, from the AI Quiz Generator):
///   mixes question types (single/multiple MCQ, true/false, fill-blank,
///   short answer) and is graded per-type, both locally (for instant
///   feedback) and server-side (for persistence/history).
class QuizScreen extends StatefulWidget {
  final int? lessonId;
  final int? subjectId;
  final String? topic;
  final List<QuizQuestionModel> questions;
  final List<QuizAttemptQuestion>? freeformQuestions;

  const QuizScreen({
    super.key,
    this.lessonId,
    this.subjectId,
    this.topic,
    this.questions = const [],
    this.freeformQuestions,
  });

  bool get isFreeform => freeformQuestions != null;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final QuizService _quizService = QuizService();
  final DateTime _startedAt = DateTime.now();

  // Lesson-mode state (single_mcq only).
  late List<int?> _selected;

  // Freeform-mode state (per question type).
  late List<int?> _ffSelectedOption;
  late List<Set<int>> _ffSelectedOptions;
  late List<TextEditingController> _ffTextControllers;

  bool _submitted = false;
  bool _saving = false;
  String? _saveError;

  List<QuizAttemptQuestion> get _ffQuestions => widget.freeformQuestions ?? [];

  @override
  void initState() {
    super.initState();
    _selected = List<int?>.filled(widget.questions.length, null);
    _ffSelectedOption = List<int?>.filled(_ffQuestions.length, null);
    _ffSelectedOptions = List.generate(_ffQuestions.length, (_) => <int>{});
    _ffTextControllers = List.generate(_ffQuestions.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _ffTextControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _allAnswered {
    if (widget.isFreeform) {
      for (var i = 0; i < _ffQuestions.length; i++) {
        final q = _ffQuestions[i];
        switch (q.questionType) {
          case QuestionTypes.multipleMcq:
            if (_ffSelectedOptions[i].isEmpty) return false;
            break;
          case QuestionTypes.fillBlank:
          case QuestionTypes.shortAnswer:
            if (_ffTextControllers[i].text.trim().isEmpty) return false;
            break;
          default:
            if (_ffSelectedOption[i] == null) return false;
        }
      }
      return true;
    }
    return _selected.every((s) => s != null);
  }

  int get _correctCount {
    if (widget.isFreeform) {
      int count = 0;
      for (var i = 0; i < _ffQuestions.length; i++) {
        if (_isFreeformCorrect(i)) count++;
      }
      return count;
    }
    int count = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      if (_selected[i] == widget.questions[i].correctOption) count++;
    }
    return count;
  }

  bool _isFreeformCorrect(int i) {
    final q = _ffQuestions[i];
    switch (q.questionType) {
      case QuestionTypes.multipleMcq:
        final selected = _ffSelectedOptions[i].toList()..sort();
        final correct = (q.correctOptions ?? [])..sort();
        return selected.length == correct.length && selected.toString() == correct.toString();
      case QuestionTypes.fillBlank:
      case QuestionTypes.shortAnswer:
        final submitted = _ffTextControllers[i].text.trim().toLowerCase();
        final correct = (q.correctText ?? '').trim().toLowerCase();
        return submitted.isNotEmpty && submitted == correct;
      default:
        return _ffSelectedOption[i] != null && _ffSelectedOption[i] == q.correctOption;
    }
  }

  int get _totalQuestions => widget.isFreeform ? _ffQuestions.length : widget.questions.length;
  int get _elapsedSeconds => DateTime.now().difference(_startedAt).inSeconds;

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _saving = true;
      _saveError = null;
    });

    if (!widget.isFreeform && widget.lessonId != null) {
      final scorePercent = ((_correctCount / widget.questions.length) * 100).round();
      await context.read<LessonProvider>().markCompleted(widget.lessonId!, score: scorePercent);
    }

    try {
      if (widget.isFreeform) {
        final answered = List.generate(_ffQuestions.length, (i) {
          final q = _ffQuestions[i];
          return q.answeredWith(
            selectedOption: _ffSelectedOption[i],
            selectedOptions: q.questionType == QuestionTypes.multipleMcq ? _ffSelectedOptions[i].toList() : null,
            submittedText: (q.questionType == QuestionTypes.fillBlank || q.questionType == QuestionTypes.shortAnswer)
                ? _ffTextControllers[i].text.trim()
                : null,
          );
        });
        await _quizService.submitFreeformAttempt(
          subjectId: widget.subjectId,
          topic: widget.topic ?? 'General',
          timeTakenSeconds: _elapsedSeconds,
          questions: answered,
        );
      } else if (widget.lessonId != null) {
        await _quizService.submitLessonAttempt(
          lessonId: widget.lessonId!,
          answers: _selected.map((s) => s ?? -1).toList(),
          timeTakenSeconds: _elapsedSeconds,
        );
      }
    } catch (e) {
      _saveError = 'Your score is shown below, but saving to history failed. Check your connection.';
    }

    if (mounted) setState(() => _saving = false);
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
              decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(18)),
              child: Column(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: AppColors.green, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'You scored $_correctCount / $_totalQuestions',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.green),
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 8),
                    const Text('Saving...', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 10),
              Text(_saveError!, style: const TextStyle(color: AppColors.error, fontSize: 12), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
          ],
          if (widget.isFreeform)
            for (var i = 0; i < _ffQuestions.length; i++) _buildFreeformQuestion(i)
          else
            for (var i = 0; i < widget.questions.length; i++) _buildLessonQuestion(i),
          const SizedBox(height: 12),
          if (!_submitted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _allAnswered ? _submit : null,
                child: const Text('Submit Quiz'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
            ),
        ],
      ),
    );
  }

  // --- Lesson mode (single_mcq only, unchanged) ---

  Widget _buildLessonQuestion(int index) {
    final q = widget.questions[index];
    return _questionCard(
      index: index,
      questionText: q.question,
      child: Column(children: [for (var j = 0; j < q.options.length; j++) _buildLessonOption(index, j, q)]),
    );
  }

  Widget _buildLessonOption(int qIndex, int optionIndex, QuizQuestionModel q) {
    final selected = _selected[qIndex] == optionIndex;
    var bg = AppColors.pageBackground;
    var fg = AppColors.textPrimary;

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

    return _optionTile(
      label: q.options[optionIndex],
      bg: bg,
      fg: fg,
      selected: selected,
      onTap: _submitted ? null : () => setState(() => _selected[qIndex] = optionIndex),
    );
  }

  // --- Freeform mode (multi-type) ---

  Widget _buildFreeformQuestion(int index) {
    final q = _ffQuestions[index];
    Widget answerWidget;
    switch (q.questionType) {
      case QuestionTypes.multipleMcq:
        answerWidget = Column(children: [for (var j = 0; j < q.options.length; j++) _buildMultiOption(index, j, q)]);
        break;
      case QuestionTypes.fillBlank:
      case QuestionTypes.shortAnswer:
        answerWidget = _buildTextAnswer(index, q);
        break;
      default:
        answerWidget = Column(children: [for (var j = 0; j < q.options.length; j++) _buildSingleOption(index, j, q)]);
    }

    return _questionCard(
      index: index,
      questionText: q.question,
      typeLabel: QuestionTypes.label(q.questionType),
      difficultyScore: q.difficultyScore,
      hint: q.hint,
      explanation: _submitted ? q.explanation : null,
      child: answerWidget,
    );
  }

  Widget _buildSingleOption(int qIndex, int optionIndex, QuizAttemptQuestion q) {
    final selected = _ffSelectedOption[qIndex] == optionIndex;
    var bg = AppColors.pageBackground;
    var fg = AppColors.textPrimary;

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

    return _optionTile(
      label: q.options[optionIndex],
      bg: bg,
      fg: fg,
      selected: selected,
      onTap: _submitted ? null : () => setState(() => _ffSelectedOption[qIndex] = optionIndex),
    );
  }

  Widget _buildMultiOption(int qIndex, int optionIndex, QuizAttemptQuestion q) {
    final selected = _ffSelectedOptions[qIndex].contains(optionIndex);
    final isCorrectOption = (q.correctOptions ?? []).contains(optionIndex);
    var bg = AppColors.pageBackground;
    var fg = AppColors.textPrimary;

    if (_submitted) {
      if (isCorrectOption) {
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

    return _optionTile(
      label: q.options[optionIndex],
      bg: bg,
      fg: fg,
      selected: selected,
      leading: Icon(
        selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        size: 18,
        color: selected ? AppColors.purple : AppColors.textSecondary,
      ),
      onTap: _submitted
          ? null
          : () => setState(() {
                if (selected) {
                  _ffSelectedOptions[qIndex].remove(optionIndex);
                } else {
                  _ffSelectedOptions[qIndex].add(optionIndex);
                }
              }),
    );
  }

  Widget _buildTextAnswer(int qIndex, QuizAttemptQuestion q) {
    final isCorrect = _submitted ? _isFreeformCorrect(qIndex) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ffTextControllers[qIndex],
          enabled: !_submitted,
          decoration: InputDecoration(
            hintText: q.questionType == QuestionTypes.fillBlank ? 'Fill in the blank...' : 'Type your answer...',
            filled: true,
            fillColor: AppColors.pageBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_submitted) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(isCorrect! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 16, color: isCorrect ? AppColors.green : AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Correct answer: ${q.correctText ?? ''}',
                  style: TextStyle(fontSize: 12, color: isCorrect ? AppColors.green : AppColors.error),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _optionTile({
    required String label,
    required Color bg,
    required Color fg,
    required bool selected,
    Widget? leading,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 10)],
              Expanded(
                child: Text(label, style: TextStyle(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionCard({
    required int index,
    required String questionText,
    required Widget child,
    String? typeLabel,
    int? difficultyScore,
    String? hint,
    String? explanation,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (typeLabel != null || difficultyScore != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                children: [
                  if (typeLabel != null) _tag(typeLabel, AppColors.blueLight, AppColors.blue),
                  if (difficultyScore != null) _tag('Difficulty $difficultyScore/10', AppColors.orangeLight, AppColors.orange),
                ],
              ),
            ),
          Text('Q${index + 1}. $questionText', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          if (hint != null && hint.isNotEmpty && !_submitted) ...[
            const SizedBox(height: 6),
            _HintReveal(hint: hint),
          ],
          const SizedBox(height: 10),
          child,
          if (_submitted && explanation != null && explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(10)),
              child: Text('Explanation: $explanation', style: const TextStyle(fontSize: 12, color: AppColors.purple)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _HintReveal extends StatefulWidget {
  final String hint;
  const _HintReveal({required this.hint});

  @override
  State<_HintReveal> createState() => _HintRevealState();
}

class _HintRevealState extends State<_HintReveal> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    if (_shown) {
      return Text('Hint: ${widget.hint}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic));
    }
    return InkWell(
      onTap: () => setState(() => _shown = true),
      child: const Text('Show hint', style: TextStyle(fontSize: 12, color: AppColors.purple, fontWeight: FontWeight.w600)),
    );
  }
}
