import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_service.dart';
import '../../widgets/skeleton_box.dart';

/// Admin-only dashboard: real platform-wide counts (students, teachers,
/// pending applications, subjects, lessons, quiz attempts, AI chat
/// sessions), plus a shortcut into the Teacher Applications review queue.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminService _adminService = AdminService();

  AdminDashboardStats? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _stats = await _adminService.fetchDashboardStats();
    } catch (e) {
      _error = 'Could not load dashboard. Please try again.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? _buildSkeleton()
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        SkeletonBox(height: 90, borderRadius: BorderRadius.all(Radius.circular(18))),
        SizedBox(height: 12),
        SkeletonBox(height: 90, borderRadius: BorderRadius.all(Radius.circular(18))),
      ],
    );
  }

  Widget _buildError() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry'))),
      ],
    );
  }

  Widget _buildContent() {
    final s = _stats!;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (s.pendingTeachers > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Material(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.push('/admin-teacher-applications'),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.person_add_alt_1_rounded, color: AppColors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${s.pendingTeachers} teacher application${s.pendingTeachers == 1 ? '' : 's'} waiting for review',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.orange),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.orange),
                    ],
                  ),
                ),
              ),
            ),
          ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _statCard('Students', '${s.totalStudents}', Icons.school_rounded, AppColors.purple, AppColors.purpleLight),
            _statCard('Teachers', '${s.totalTeachers}', Icons.person_rounded, AppColors.blue, AppColors.blueLight),
            _statCard('Subjects', '${s.totalSubjects}', Icons.menu_book_rounded, AppColors.green, AppColors.greenLight),
            _statCard('Lessons', '${s.totalLessons}', Icons.play_lesson_rounded, AppColors.orange, AppColors.orangeLight),
            _statCard('Quiz Attempts', '${s.totalQuizAttempts}', Icons.quiz_rounded, AppColors.purple, AppColors.purpleLight),
            _statCard('AI Chat Sessions', '${s.totalAiChatSessions}', Icons.smart_toy_rounded, AppColors.blue, AppColors.blueLight),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
          child: Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: AppColors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${s.newRegistrationsThisWeek} new registration${s.newRegistrationsThisWeek == 1 ? '' : 's'} this week',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/admin-teacher-applications'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
              child: const Row(
                children: [
                  Icon(Icons.fact_check_rounded, color: AppColors.purple),
                  SizedBox(width: 12),
                  Expanded(child: Text('Review Teacher Applications', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/admin-assignments'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
              child: const Row(
                children: [
                  Icon(Icons.assignment_rounded, color: AppColors.blue),
                  SizedBox(width: 12),
                  Expanded(child: Text('Assignments Monitoring', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/admin-live-classes'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
              child: const Row(
                children: [
                  Icon(Icons.video_camera_front_rounded, color: AppColors.orange),
                  SizedBox(width: 12),
                  Expanded(child: Text('Live Classes Monitoring', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
