import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/course_model.dart';
import '../../services/course_service.dart';
import 'create_edit_course_screen.dart';
import 'course_categories_screen.dart';
import 'lesson_management_screen.dart';

/// Admin-only Course Management: search, filter by category/status,
/// create/edit/delete/publish courses. Every action here hits an
/// admin-gated backend endpoint.
class AdminCourseManagementScreen extends StatefulWidget {
  const AdminCourseManagementScreen({super.key});

  @override
  State<AdminCourseManagementScreen> createState() => _AdminCourseManagementScreenState();
}

class _AdminCourseManagementScreenState extends State<AdminCourseManagementScreen> {
  final CourseService _service = CourseService();
  final TextEditingController _searchController = TextEditingController();

  List<AdminCourseModel> _courses = [];
  bool _loading = true;
  String? _error;
  int? _categoryFilter;
  String? _statusFilter; // null = all, 'draft', 'published'
  List<Map<String, dynamic>> _categories = []; // {id, name}

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _service.listCategories();
      if (mounted) setState(() => _categories = cats.map((c) => {'id': c.id, 'name': c.name}).toList());
    } catch (_) {
      // best-effort - filter chips just won't show category names
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _courses = await _service.listCourses(
        search: _searchController.text.trim(),
        categoryId: _categoryFilter,
        status: _statusFilter,
      );
    } catch (e) {
      _error = 'Could not load courses.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _confirmDelete(AdminCourseModel course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Course?'),
        content: Text('This will permanently delete "${course.name}" and all its lessons. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteCourse(course.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Course deleted.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete course.')));
    }
  }

  Future<void> _togglePublish(AdminCourseModel course) async {
    try {
      if (course.status == 'published') {
        await _service.unpublishCourse(course.id);
      } else {
        await _service.publishCourse(course.id);
      }
      _load();
    } catch (e) {
      if (mounted) {
        final message = course.status == 'published'
            ? 'Failed to unpublish course.'
            : 'At least one lesson is required before publishing.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Course Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Manage Categories',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const CourseCategoriesScreen()));
              _loadCategories();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const CreateEditCourseScreen()),
          );
          if (created == true) _load();
        },
        backgroundColor: AppColors.purple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search courses...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _filterChip('All Status', _statusFilter == null, () {
                  setState(() => _statusFilter = null);
                  _load();
                }),
                _filterChip('Published', _statusFilter == 'published', () {
                  setState(() => _statusFilter = 'published');
                  _load();
                }),
                _filterChip('Draft', _statusFilter == 'draft', () {
                  setState(() => _statusFilter = 'draft');
                  _load();
                }),
                const SizedBox(width: 8),
                Container(width: 1, color: AppColors.textSecondary.withOpacity(0.2)),
                const SizedBox(width: 8),
                _filterChip('All Categories', _categoryFilter == null, () {
                  setState(() => _categoryFilter = null);
                  _load();
                }),
                for (final cat in _categories)
                  _filterChip(cat['name'] as String, _categoryFilter == cat['id'], () {
                    setState(() => _categoryFilter = cat['id'] as int);
                    _load();
                  }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _courses.isEmpty
                        ? const Center(child: Text('No courses found.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              itemCount: _courses.length,
                              itemBuilder: (context, index) => _courseCard(_courses[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.purple,
        labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontSize: 13),
      ),
    );
  }

  Widget _courseCard(AdminCourseModel course) {
    final isPublished = course.status == 'published';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonManagementScreen(courseId: course.id, courseName: course.name))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: course.thumbnail.isNotEmpty
                    ? Image.network(course.thumbnail, width: 72, height: 72, fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _thumbPlaceholder())
                    : _thumbPlaceholder(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(course.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPublished ? AppColors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isPublished ? 'Published' : 'Draft',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isPublished ? AppColors.green : Colors.orange),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(course.categoryName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.menu_book_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('${course.totalLessons} lessons', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(width: 12),
                        const Icon(Icons.people_alt_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('${course.enrolledCount} enrolled', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    final updated = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => CreateEditCourseScreen(course: course)),
                    );
                    if (updated == true) _load();
                  } else if (value == 'lessons') {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => LessonManagementScreen(courseId: course.id, courseName: course.name)));
                  } else if (value == 'publish') {
                    _togglePublish(course);
                  } else if (value == 'delete') {
                    _confirmDelete(course);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'lessons', child: Text('Manage Lessons')),
                  PopupMenuItem(value: 'publish', child: Text(isPublished ? 'Unpublish' : 'Publish')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.purpleLight,
      child: const Icon(Icons.school_rounded, color: AppColors.purple, size: 28),
    );
  }
}
