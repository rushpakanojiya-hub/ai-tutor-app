import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/student_class_section_model.dart';
import '../../services/leaderboard_service.dart';

/// Admin-only: assign/update each student's Class and Section - used
/// purely for Leaderboard filtering, nowhere else.
class ManageStudentsScreen extends StatefulWidget {
  const ManageStudentsScreen({super.key});

  @override
  State<ManageStudentsScreen> createState() => _ManageStudentsScreenState();
}

class _ManageStudentsScreenState extends State<ManageStudentsScreen> {
  final LeaderboardService _service = LeaderboardService();
  List<StudentClassSectionModel> _students = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _students = await _service.listStudents();
    } catch (e) {
      _error = 'Could not load students.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _editClassSection(StudentClassSectionModel student) async {
    final classController = TextEditingController(text: student.classValue);
    final sectionController = TextEditingController(text: student.section);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(student.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: classController, decoration: const InputDecoration(labelText: 'Class')),
            const SizedBox(height: 12),
            TextField(controller: sectionController, decoration: const InputDecoration(labelText: 'Section')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;

    try {
      await _service.assignClassSection(student.id, classValue: classController.text.trim(), section: sectionController.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Students')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final s = _students[index];
                      final hasClassSection = s.classValue.isNotEmpty || s.section.isNotEmpty;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: AppColors.purple, child: Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                          title: Text(s.name),
                          subtitle: Text(hasClassSection ? 'Class ${s.classValue} - Section ${s.section}' : 'No class/section assigned'),
                          trailing: const Icon(Icons.edit_outlined, color: AppColors.purple),
                          onTap: () => _editClassSection(s),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
