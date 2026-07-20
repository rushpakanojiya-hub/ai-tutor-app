import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subject_model.dart';
import '../../services/live_class_service.dart';
import '../../services/subject_service.dart';

/// Teacher schedules a class - date/time/subject/capacity only. No
/// "Start Class" here since there's no video backend yet.
class CreateLiveClassScreen extends StatefulWidget {
  const CreateLiveClassScreen({super.key});

  @override
  State<CreateLiveClassScreen> createState() => _CreateLiveClassScreenState();
}

class _CreateLiveClassScreenState extends State<CreateLiveClassScreen> {
  final LiveClassService _service = LiveClassService();
  final SubjectService _subjectService = SubjectService();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxStudentsController = TextEditingController();

  List<SubjectModel> _subjects = [];
  int? _selectedSubjectId;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);
  bool _loadingSubjects = true;
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

  String _fmtDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _schedule() async {
    if (_selectedSubjectId == null || _titleController.text.trim().isEmpty) {
      setState(() => _error = 'Subject and title are required.');
      return;
    }

    final maxStudents = int.tryParse(_maxStudentsController.text.trim());
    if (maxStudents == null || maxStudents < 1) {
      setState(() => _error = 'Maximum Students is required and must be a valid number.');
      return;
    }

    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    if (endMinutes <= startMinutes) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.create(
        subjectId: _selectedSubjectId!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        classDate: _fmtDate(_date),
        startTime: _fmtTime(_startTime),
        endTime: _fmtTime(_endTime),
        maxStudents: maxStudents,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Class scheduled.')));
        context.pop();
      }
    } catch (e) {
      setState(() => _error = 'Failed to schedule class. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _maxStudentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Schedule Live Class')),
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
          _card(title: 'Title', child: TextField(controller: _titleController, decoration: const InputDecoration(border: OutlineInputBorder()))),
          const SizedBox(height: 14),
          _card(title: 'Description', child: TextField(controller: _descriptionController, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder()))),
          const SizedBox(height: 14),
          _card(
            title: 'Date',
            child: Row(
              children: [
                Expanded(child: Text(_fmtDate(_date))),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (picked != null && mounted) setState(() => _date = picked);
                  },
                  child: const Text('Pick date'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _card(
                  title: 'Start Time',
                  child: Row(
                    children: [
                      Expanded(child: Text(_startTime.format(context))),
                      TextButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: _startTime);
                          if (picked != null && mounted) setState(() => _startTime = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _card(
                  title: 'End Time',
                  child: Row(
                    children: [
                      Expanded(child: Text(_endTime.format(context))),
                      TextButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: _endTime);
                          if (picked != null && mounted) setState(() => _endTime = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _card(
            title: 'Maximum Students *',
            child: TextField(
              controller: _maxStudentsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Required'),
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
              onPressed: _saving ? null : _schedule,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppColors.purple),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Schedule Class'),
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
