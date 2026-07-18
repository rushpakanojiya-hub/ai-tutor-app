import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/category_model.dart';
import '../../models/course_model.dart';
import '../../services/course_service.dart';

/// Create a new course, or edit an existing one if [course] is passed.
/// Course Name is the only required field, matching the QA spec.
class CreateEditCourseScreen extends StatefulWidget {
  final AdminCourseModel? course;
  const CreateEditCourseScreen({super.key, this.course});

  @override
  State<CreateEditCourseScreen> createState() => _CreateEditCourseScreenState();
}

class _CreateEditCourseScreenState extends State<CreateEditCourseScreen> {
  final CourseService _service = CourseService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _thumbnailController;

  List<CategoryModel> _categories = [];
  int? _selectedCategoryId;
  String _difficulty = 'Intermediate';
  bool _saving = false;
  bool _loadingCategories = true;

  bool get _isEdit => widget.course != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.course?.name ?? '');
    _descriptionController = TextEditingController(text: widget.course?.description ?? '');
    _thumbnailController = TextEditingController(text: widget.course?.thumbnail ?? '');
    _difficulty = widget.course?.difficulty ?? 'Intermediate';
    _selectedCategoryId = widget.course?.categoryId;
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _thumbnailController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      _categories = await _service.listCategories();
      final savedCategoryExists = _categories.any((c) => c.id == _selectedCategoryId);
      if (!savedCategoryExists) {
        _selectedCategoryId = _categories.isNotEmpty ? _categories.first.id : null;
      }
    } catch (_) {
      // best-effort
    }
    if (mounted) setState(() => _loadingCategories = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a category.')));
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _service.updateCourse(
          widget.course!.id,
          categoryId: _selectedCategoryId,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          thumbnail: _thumbnailController.text.trim(),
          difficulty: _difficulty,
        );
      } else {
        await _service.createCourse(
          categoryId: _selectedCategoryId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          thumbnail: _thumbnailController.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEdit ? 'Failed to update course.' : 'Failed to create course.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Course' : 'Create Course')),
      body: _loadingCategories
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Course Name *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Course name is required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _thumbnailController,
                    decoration: const InputDecoration(labelText: 'Thumbnail URL', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'Category *', border: OutlineInputBorder()),
                    items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _difficulty,
                    decoration: const InputDecoration(labelText: 'Difficulty', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Beginner', child: Text('Beginner')),
                      DropdownMenuItem(value: 'Intermediate', child: Text('Intermediate')),
                      DropdownMenuItem(value: 'Advanced', child: Text('Advanced')),
                    ],
                    onChanged: (v) => setState(() => _difficulty = v ?? 'Intermediate'),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: AppColors.purple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(_isEdit ? 'Save Changes' : 'Create Course', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
