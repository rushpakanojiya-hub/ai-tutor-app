import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/course_model.dart';
import '../../services/course_service.dart';
import 'lesson_management_screen.dart';

/// Teacher entry point for Lesson Resource Management: browse existing
/// courses (read-only - no add/delete/category actions, those stay
/// admin-only) and tap into a course to manage its lessons - create/
/// edit, upload video (or paste a YouTube URL), upload PDF notes, and
/// publish/unpublish. Reuses the exact same LessonManagementScreen the
/// admin panel uses, since the backend already accepts admin or teacher
/// for all lesson actions.
class TeacherLessonsScreen extends StatefulWidget {
  const TeacherLessonsScreen({super.key});

  @override
  State<TeacherLessonsScreen> createState() => _TeacherLessonsScreenState();
}

class _TeacherLessonsScreenState extends State<TeacherLessonsScreen> {
  final CourseService _service = CourseService();
  final TextEditingController _searchController = TextEditingController();

  List<AdminCourseModel> _courses = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _courses = await _service.listCourses(search: _searchController.text.trim());
    } catch (e) {
      _error = 'Could not load courses.';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Lessons')),
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
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _courses.isEmpty
                        ? const Center(child: Text('No courses found yet.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: _courses.length,
                              itemBuilder: (context, index) => _courseCard(_courses[index]),
                            ),
                          ),
          ),
        ],
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
                    ? Image.network(course.thumbnail, width: 64, height: 64, fit: BoxFit.cover,
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
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      color: AppColors.purpleLight,
      child: const Icon(Icons.school_rounded, color: AppColors.purple, size: 26),
    );
  }
}