import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'edit_profile_screen.dart';
import '../badges/my_badges_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../leaderboard/manage_students_screen.dart';
import '../certificates/my_certificates_screen.dart';

/// Profile tab: shows the logged-in user's info and a logout button.
/// UI redesign only â€” AuthProvider.logout() and the navigation after it
/// are exactly what they were before.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(color: AppColors.purpleLight, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      (user?.name.isNotEmpty == true ? user!.name[0] : '?').toUpperCase(),
                      style: const TextStyle(fontSize: 34, color: AppColors.purple, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(user?.name ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    (user?.role ?? '-').toUpperCase(),
                    style: const TextStyle(color: AppColors.purple, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),

          const SizedBox(height: 20),

          _ProfileMenuTile(
            icon: Icons.edit_outlined,
            label: 'Edit Profile',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
            },
          ).animate().fadeIn(duration: 250.ms, delay: 100.ms),
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.bar_chart_rounded,
            label: 'Quiz Analytics',
            onTap: () => context.push('/quiz-analytics'),
          ).animate().fadeIn(duration: 250.ms, delay: 130.ms),
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.auto_awesome_rounded,
            label: 'AI Quiz Generator',
            onTap: () => context.push('/ai-quiz-generator'),
          ).animate().fadeIn(duration: 250.ms, delay: 145.ms),
          _ProfileMenuTile(
            icon: Icons.leaderboard_rounded,
            label: 'Leaderboard',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
            },
          ).animate().fadeIn(duration: 250.ms, delay: 130.ms),
          if (auth.currentUser?.role == 'student') ...[
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.video_camera_front_rounded,
              label: 'Live Classes',
              onTap: () => context.push('/student-live-classes'),
            ).animate().fadeIn(duration: 250.ms, delay: 147.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.emoji_events_rounded,
              label: 'My Badges',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBadgesScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 160.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.workspace_premium_rounded,
              label: 'My Certificates',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCertificatesScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 165.ms),
          ],
          if (auth.currentUser?.role == 'teacher') ...[
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.assignment_rounded,
              label: 'My Assignments',
              onTap: () => context.push('/my-assignments'),
            ).animate().fadeIn(duration: 250.ms, delay: 148.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.video_camera_front_rounded,
              label: 'My Live Classes',
              onTap: () => context.push('/my-live-classes'),
            ).animate().fadeIn(duration: 250.ms, delay: 149.ms),
          ],
          if (auth.currentUser?.role == 'admin') ...[
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.admin_panel_settings_rounded,
              label: 'Admin Panel',
              onTap: () => context.push('/admin-dashboard'),
            ).animate().fadeIn(duration: 250.ms, delay: 150.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.groups_rounded,
              label: 'Manage Students',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageStudentsScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 155.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.workspace_premium_rounded,
              label: 'All Certificates',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCertificatesScreen(mode: CertificateListMode.admin)));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 156.ms),
          ],
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.logout_rounded,
            label: 'Logout',
            color: AppColors.error,
            onTap: () async {
              await context.read<AuthProvider>().logout();
              if (context.mounted) context.go('/login');
            },
          ).animate().fadeIn(duration: 250.ms, delay: 160.ms),
        ],
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ProfileMenuTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.textPrimary;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 22),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w600, fontSize: 15))),
              Icon(Icons.chevron_right_rounded, color: tint.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
