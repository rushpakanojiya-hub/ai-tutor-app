import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subject_model.dart';
import '../../services/assignment_service.dart';
import '../../services/subject_service.dart';

/// Teacher creates an assignment for a Subject (Phase 1 targeting).
/// "Generate with AI" fills the form with a draft the teacher can edit
/// before saving - nothing is created until they tap "Create Assignment".
class CreateAssignmentScreen extends StatefulWidget {
  const CreateAssignmentScreen({super.key});

  @override
  State<CreateAssignmentScreen> createState() => _CreateAssignmentScreenState();
}

class _CreateAssignmentScreenState extends State<CreateAssignmentScreen> {
  final AssignmentService _assignmentService = AssignmentService();
  final SubjectService _subjectService = SubjectService();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _topicController = TextEditingController();
  final _maxMarksController = TextEditingController(text: '10');

  List<SubjectModel> _subjects = [];
  int? _selectedSubjectId;
  String _difficulty = 'medium';
  int _estimatedMinutes = 30;
  DateTime? _dueDate;
  bool _loadingSubjects = true;
  bool _generating = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      _subjects = await _subjectService.fetchAllSubjects();
    } catch (_) {}
    if (mounted) setState(() => _loadingSubjects = false);
  }

  Future<void> _generateWithAI() async {
    if (_selectedSubjectId == null) {
      setState(() => _error = 'Select a subject first.');
      return;
    }
    if (_topicController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a topic for the AI to generate from.');
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final draft = await _assignmentService.generateWithAI(
        subjectId: _selectedSubjectId!,
        topic: _topicController.text.trim(),
        difficulty: _difficulty,
      );
      if (!mounted) return;
      _titleController.text = draft.title;
      _descriptionController.text = draft.description;
      _instructionsController.text = draft.instructions;
      _estimatedMinutes = draft.estimatedMinutes;
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not generate a draft. Please try again or fill it in manually.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _create() async {
    if (_selectedSubjectId == null || _titleController.text.trim().isEmpty) {
      setState(() => _error = 'Subject and title are required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _assignmentService.create(
        subjectId: _selectedSubjectId!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        instructions: _instructionsController.text.trim(),
        difficulty: _difficulty,
        estimatedMinutes: _estimatedMinutes,
        maxMarks: int.tryParse(_maxMarksController.text) ?? 10,
        dueDate: _dueDate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment created as a draft. Publish it when ready.')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to create assignment. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _instructionsController.dispose();
    _topicController.dispose();
    _maxMarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Create Assignment')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(
            title: 'Subject',
            child: _loadingSubjects
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<int?>(
                    value: _selectedSubjectId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Select a subject'),
                    items: _subjects.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))).toList(),
                    onChanged: (v) => setState(() => _selectedSubjectId = v),
                  ),
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Generate with AI (optional)',
            child: Column(
              children: [
                TextField(
                  controller: _topicController,
                  decoration: const InputDecoration(hintText: 'Topic, e.g. Photosynthesis', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _generating ? null : _generateWithAI,
                    icon: _generating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(_generating ? 'Generating...' : 'Generate with AI'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Title',
            child: TextField(controller: _titleController, decoration: const InputDecoration(border: OutlineInputBorder())),
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Description',
            child: TextField(controller: _descriptionController, maxLines: 2, decoration: const InputDecoration(border: OutlineInputBorder())),
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Instructions for the student',
            child: TextField(controller: _instructionsController, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder())),
          ),
          const SizedBox(height: 14),
          _card(
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
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Max Marks',
            child: TextField(controller: _maxMarksController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder())),
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Due Date (optional)',
            child: Row(
              children: [
                Expanded(child: Text(_dueDate == null ? 'No due date set' : '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}')),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _dueDate = picked);
                  },
                  child: const Text('Pick date'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _create,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppColors.purple),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create Assignment'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
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
