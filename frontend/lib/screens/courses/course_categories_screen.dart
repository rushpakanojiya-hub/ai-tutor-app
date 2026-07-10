import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/category_model.dart';
import '../../services/course_service.dart';

/// Admin-only: create and rename Course Categories (the top level of the
/// Category -> Course -> Lesson hierarchy).
class CourseCategoriesScreen extends StatefulWidget {
  const CourseCategoriesScreen({super.key});

  @override
  State<CourseCategoriesScreen> createState() => _CourseCategoriesScreenState();
}

class _CourseCategoriesScreenState extends State<CourseCategoriesScreen> {
  final CourseService _service = CourseService();
  List<CategoryModel> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _categories = await _service.listCategories();
    } catch (_) {
      // best-effort
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _showCategoryDialog({CategoryModel? existing}) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(existing == null ? 'New Category' : 'Rename Category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Category Name'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
          ],
        ),
      );
      if (result == null || result.isEmpty) return;

      try {
        if (existing == null) {
          await _service.createCategory(result);
        } else {
          await _service.updateCategory(existing.id, name: result);
        }
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save category.')));
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Course Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCategoryDialog(),
        backgroundColor: AppColors.purple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
              ? const Center(child: Text('No categories yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.folder_outlined, color: AppColors.purple),
                        title: Text(cat.name),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _showCategoryDialog(existing: cat),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
