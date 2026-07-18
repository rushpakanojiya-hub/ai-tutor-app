import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_service.dart';

/// Admin-only: every student's lessons completed, average quiz score,
/// and current learning streak in one place. Read-only overview - no
/// editing happens here, per-student changes still happen wherever
/// they already happen (class/section assignment, etc.).
class StudentProgressScreen extends StatefulWidget {
  const StudentProgressScreen({super.key});

  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _searchController = TextEditingController();

  List<StudentProgressModel> _all = [];
  List<StudentProgressModel> _filtered = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _all = await _adminService.fetchStudentProgress();
      _applyFilter();
    } catch (e) {
      _error = 'Could not load student progress.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _all
          : _all.where((s) => s.name.toLowerCase().contains(query) || s.email.toLowerCase().contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Student Progress'),
        elevation: 0,
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textPrimary,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
                    ],
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by name or email...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          ),
        ),
        const SizedBox(height: 8),
        Text('${_filtered.length} student${_filtered.length == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        if (_filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No students found.', style: TextStyle(color: AppColors.textSecondary))),
          )
        else
          ..._filtered.map(_studentCard),
      ],
    );
  }

  Widget _studentCard(StudentProgressModel s) {
    final classSection = [s.classValue, s.section].where((v) => v.isNotEmpty).join(' - ');
    final percent = (s.completionPercent * 100).clamp(0, 100);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.purpleLight,
                child: Text(
                  s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(s.email, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    if (classSection.isNotEmpty)
                      Text(classSection, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (s.currentStreak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('\u{1F525}', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text('${s.currentStreak}d', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.orange)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Lessons completed', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text('${s.lessonsCompleted}/${s.totalLessons} (${percent.toStringAsFixed(0)}%)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: s.completionPercent.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: AppColors.pageBackground,
                        color: AppColors.purple,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.quiz_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                s.averageQuizScore != null ? 'Avg quiz score: ${s.averageQuizScore!.toStringAsFixed(0)}%' : 'No quiz attempts yet',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}