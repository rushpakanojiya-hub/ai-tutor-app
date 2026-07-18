import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/quiz_attempt_model.dart';
import '../../models/subject_model.dart';
import '../../services/quiz_service.dart';
import '../../services/subject_service.dart';

/// Lets a student generate a fresh AI quiz on any topic - independent of
/// any specific lesson. Picks a subject (optional, for tagging/analytics),
/// types a topic, chooses difficulty, question types, and question count,
/// then launches QuizScreen in freeform mode.
class AiQuizGeneratorScreen extends StatefulWidget {
  const AiQuizGeneratorScreen({super.key});

  @override
  State<AiQuizGeneratorScreen> createState() => _AiQuizGeneratorScreenState();
}

class _AiQuizGeneratorScreenState extends State<AiQuizGeneratorScreen> {
  final QuizService _quizService = QuizService();
  final SubjectService _subjectService = SubjectService();

  List<SubjectModel> _subjects = [];
  int? _selectedSubjectId;
  String _difficulty = 'medium';
  int _numQuestions = 5;
  final Set<String> _selectedTypes = {QuestionTypes.singleMcq};
  bool _loadingSubjects = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      _subjects = await _subjectService.fetchAllSubjects();
    } catch (_) {
      _subjects = [];
    }
    if (mounted) setState(() => _loadingSubjects = false);
  }

  Future<void> _generate() async {
    if (_selectedSubjectId == null) {
      setState(() => _error = 'Please select a subject.');
      return;
    }
    if (_selectedTypes.isEmpty) {
      setState(() => _error = 'Please select at least one question type.');
      return;
    }

    final subject = _subjects.firstWhere((s) => s.id == _selectedSubjectId);
    final topic = subject.name;

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final questions = await _quizService.generateQuiz(
        subjectId: _selectedSubjectId,
        topic: topic,
        numQuestions: _numQuestions,
        difficulty: _difficulty,
        questionTypes: _selectedTypes.toList(),
      );

      if (questions.isEmpty) {
        if (mounted) {
          setState(() {
            _generating = false;
            _error = 'Could not generate a quiz for that subject. Please try again.';
          });
        }
        return;
      }

      if (mounted) {
        context.push(
          '/quiz',
          extra: {
            'subjectId': _selectedSubjectId,
            'topic': topic,
            'freeformQuestions': questions,
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong generating the quiz. Please try again.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('AI Quiz Generator')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Generate a quiz for any subject', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Pick a subject, question types, and difficulty to get a fresh AI-written quiz.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),

          _sectionCard(
            title: 'Subject',
            child: _loadingSubjects
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<int?>(
                    value: _selectedSubjectId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Select a subject'),
                    items: _subjects.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))).toList(),
                    onChanged: (value) => setState(() => _selectedSubjectId = value),
                  ),
          ),
          const SizedBox(height: 14),

          _sectionCard(
            title: 'Question Types (select one or more)',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: QuestionTypes.all.map((type) {
                final selected = _selectedTypes.contains(type);
                return FilterChip(
                  label: Text(QuestionTypes.label(type), style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    if (value) {
                      _selectedTypes.add(type);
                    } else {
                      _selectedTypes.remove(type);
                    }
                  }),
                  selectedColor: AppColors.purpleLight,
                  checkmarkColor: AppColors.purple,
                  labelStyle: TextStyle(color: selected ? AppColors.purple : AppColors.textSecondary),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          _sectionCard(
            title: 'Difficulty',
            child: Wrap(
              spacing: 8,
              children: ['easy', 'medium', 'hard'].map((d) {
                final selected = _difficulty == d;
                return ChoiceChip(
                  label: Text(d[0].toUpperCase() + d.substring(1)),
                  selected: selected,
                  onSelected: (_) => setState(() => _difficulty = d),
                  selectedColor: AppColors.purpleLight,
                  labelStyle: TextStyle(color: selected ? AppColors.purple : AppColors.textSecondary),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          _sectionCard(
            title: 'Number of Questions: $_numQuestions',
            child: Slider(
              value: _numQuestions.toDouble(),
              min: 3,
              max: 10,
              divisions: 7,
              label: '$_numQuestions',
              activeColor: AppColors.purple,
              onChanged: (value) => setState(() => _numQuestions = value.round()),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _generate,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppColors.purple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _generating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_generating ? 'Generating...' : 'Generate Quiz'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
