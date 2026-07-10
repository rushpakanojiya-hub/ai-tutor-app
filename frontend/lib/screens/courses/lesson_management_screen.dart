import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/course_model.dart';
import '../../services/course_service.dart';

/// Admin-only: manage a course's lessons - create, edit, delete, drag-
/// and-drop reorder, and upload video/PDF/assignment files (via
/// Cloudinary, same pattern as Class Resources uploads elsewhere).
class LessonManagementScreen extends StatefulWidget {
  final int courseId;
  final String courseName;
  const LessonManagementScreen({super.key, required this.courseId, required this.courseName});

  @override
  State<LessonManagementScreen> createState() => _LessonManagementScreenState();
}

class _LessonManagementScreenState extends State<LessonManagementScreen> {
  final CourseService _service = CourseService();
  List<AdminLessonModel> _lessons = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _lessons = await _service.listLessons(widget.courseId);
    } catch (_) {
      // best-effort
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _lessons.removeAt(oldIndex);
      _lessons.insert(newIndex, item);
    });
    final items = [
      for (var i = 0; i < _lessons.length; i++) {'id': _lessons[i].id, 'order_number': i}
    ];
    try {
      await _service.reorderLessons(widget.courseId, items);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save new order.')));
      _load();
    }
  }

  Future<void> _showLessonDialog({AdminLessonModel? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    final durationController = TextEditingController(text: existing != null ? existing.duration.toString() : '');

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(existing == null ? 'New Lesson' : 'Edit Lesson'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleController, autofocus: true, decoration: const InputDecoration(labelText: 'Title *')),
                const SizedBox(height: 12),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
                const SizedBox(height: 12),
                TextField(controller: durationController, decoration: const InputDecoration(labelText: 'Duration (minutes)'), keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      );
      if (saved != true) return;
      if (titleController.text.trim().isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title is required.')));
        return;
      }

      try {
        final duration = int.tryParse(durationController.text.trim()) ?? 0;
        if (existing == null) {
          await _service.createLesson(
            subjectId: widget.courseId,
            title: titleController.text.trim(),
            description: descController.text.trim(),
            duration: duration,
            orderNumber: _lessons.length,
          );
        } else {
          await _service.updateLesson(existing.id, title: titleController.text.trim(), description: descController.text.trim(), duration: duration);
        }
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save lesson.')));
      }
    } finally {
      titleController.dispose();
      descController.dispose();
      durationController.dispose();
    }
  }

  Future<void> _confirmDeleteLesson(AdminLessonModel lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Lesson?'),
        content: Text('Delete "${lesson.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteLesson(lesson.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete lesson.')));
    }
  }

  Future<void> _uploadFile(AdminLessonModel lesson, String kind) async {
    final extensions = kind == 'video' ? ['mp4', 'mov'] : ['pdf'];
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensions);
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploading ${kind}...'), duration: const Duration(seconds: 30)));

    try {
      if (kind == 'video') {
        await _service.uploadLessonVideo(lesson.id, file);
      } else if (kind == 'pdf') {
        await _service.uploadLessonPdf(lesson.id, file);
      } else {
        await _service.uploadLessonAssignment(lesson.id, file);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload complete.')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Lessons - ${widget.courseName}')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showLessonDialog(),
        backgroundColor: AppColors.purple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lessons.isEmpty
              ? const Center(child: Text('No lessons yet. Tap + to add one.'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _lessons.length,
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                    final lesson = _lessons[index];
                    return Card(
                      key: ValueKey(lesson.id),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        leading: CircleAvatar(backgroundColor: AppColors.purpleLight, child: Text('${index + 1}', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700))),
                        title: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(lesson.duration > 0 ? '${lesson.duration} min' : 'No duration set', style: const TextStyle(fontSize: 12)),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary)),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _actionChip(Icons.videocam_outlined, lesson.videoUrl.isNotEmpty ? 'Video ✓' : 'Upload Video', () => _uploadFile(lesson, 'video')),
                                    _actionChip(Icons.picture_as_pdf_outlined, lesson.pdfUrl.isNotEmpty ? 'PDF ✓' : 'Upload PDF', () => _uploadFile(lesson, 'pdf')),
                                    _actionChip(Icons.assignment_outlined, lesson.assignmentUrl.isNotEmpty ? 'Assignment ✓' : 'Upload Assignment', () => _uploadFile(lesson, 'assignment')),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _showLessonDialog(existing: lesson),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      label: const Text('Edit'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _confirmDeleteLesson(lesson),
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.purple),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}
