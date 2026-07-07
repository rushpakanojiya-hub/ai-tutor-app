import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_service.dart';
import '../../widgets/skeleton_box.dart';

/// Admin's queue of pending teacher applications - approve or reject each
/// one. Approving flips the account to active (they can log in); rejecting
/// flips it to rejected (they still can't). Both call the real backend
/// endpoints built alongside the teacher-application auth flow.
class TeacherApplicationsScreen extends StatefulWidget {
  const TeacherApplicationsScreen({super.key});

  @override
  State<TeacherApplicationsScreen> createState() => _TeacherApplicationsScreenState();
}

class _TeacherApplicationsScreenState extends State<TeacherApplicationsScreen> {
  final AdminService _adminService = AdminService();

  List<TeacherApplicationModel> _applications = [];
  bool _isLoading = true;
  String? _error;
  final Set<int> _processingIds = {};

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
      _applications = await _adminService.fetchPendingTeachers();
    } catch (e) {
      _error = 'Could not load applications. Please try again.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _approve(TeacherApplicationModel app) async {
    setState(() => _processingIds.add(app.id));
    try {
      await _adminService.approveTeacher(app.id);
      setState(() => _applications.removeWhere((a) => a.id == app.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${app.name} approved - they can now log in.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to approve. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(app.id));
    }
  }

  Future<void> _reject(TeacherApplicationModel app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject application?'),
        content: Text('${app.name} will not be able to log in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _processingIds.add(app.id));
    try {
      await _adminService.rejectTeacher(app.id);
      setState(() => _applications.removeWhere((a) => a.id == app.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${app.name} rejected.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to reject. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(app.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: const Text('Teacher Applications')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? _buildSkeleton()
            : _error != null
                ? _buildError()
                : _applications.isEmpty
                    ? _buildEmpty()
                    : _buildList(),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: List.generate(3, (_) => const Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonBox(height: 140, borderRadius: BorderRadius.all(Radius.circular(20))))),
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

  Widget _buildEmpty() {
    return ListView(
      children: const [
        SizedBox(height: 100),
        Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.green),
        SizedBox(height: 12),
        Center(child: Text('No pending applications.', style: TextStyle(color: AppColors.textSecondary))),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _applications.length,
      itemBuilder: (context, index) {
        final app = _applications[index];
        final processing = _processingIds.contains(app.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: AppColors.purpleLight, shape: BoxShape.circle),
                    child: Center(
                      child: Text(app.name.isNotEmpty ? app.name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(app.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (app.qualification.isNotEmpty) _infoRow('Qualification', app.qualification),
              if (app.experience.isNotEmpty) _infoRow('Experience', app.experience),
              if (app.subjects.isNotEmpty) _infoRow('Subjects', app.subjects),
              if (app.phone.isNotEmpty) _infoRow('Phone', app.phone),
              if (app.bio.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(app.bio, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: processing ? null : () => _reject(app),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: processing ? null : () => _approve(app),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.green),
                      child: processing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
