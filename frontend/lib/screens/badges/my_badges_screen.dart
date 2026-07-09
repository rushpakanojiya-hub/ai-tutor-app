import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/badge_model.dart';
import '../../services/badge_service.dart';

/// "My Badges" page - students view their own progress, teachers/admins
/// can view a specific student's badges (view-only) via [studentId].
class MyBadgesScreen extends StatefulWidget {
  final int? studentId; // null = the logged-in student's own badges
  final String? studentName; // for the app bar when viewing someone else's

  const MyBadgesScreen({super.key, this.studentId, this.studentName});

  @override
  State<MyBadgesScreen> createState() => _MyBadgesScreenState();
}

class _MyBadgesScreenState extends State<MyBadgesScreen> {
  final BadgeService _badgeService = BadgeService();
  List<BadgeModel> _badges = [];
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
      _badges = widget.studentId == null
          ? await _badgeService.fetchMine()
          : await _badgeService.fetchForStudent(widget.studentId!);
    } catch (e) {
      _error = 'Could not load badges.';
    }
    if (mounted) setState(() => _loading = false);
  }

  IconData _iconFor(String iconKey) {
    switch (iconKey) {
      case 'quiz':
        return Icons.quiz_rounded;
      case 'homework':
        return Icons.assignment_turned_in_rounded;
      case 'streak':
        return Icons.local_fire_department_rounded;
      case 'math':
        return Icons.calculate_rounded;
      case 'perfect':
        return Icons.star_rounded;
      case 'course':
        return Icons.school_rounded;
      case 'attendance':
        return Icons.event_available_rounded;
      default:
        return Icons.emoji_events_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unlockedCount = _badges.where((b) => b.unlocked).length;

    return Scaffold(
      appBar: AppBar(title: Text(widget.studentName != null ? "${widget.studentName}'s Badges" : 'My Badges')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_events_rounded, color: AppColors.purple, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$unlockedCount of ${_badges.length} badges earned', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text('Keep learning to unlock more!', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: _badges.length,
                        itemBuilder: (context, index) => _badgeCard(_badges[index]),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _badgeCard(BadgeModel badge) {
    return Card(
      elevation: badge.unlocked ? 2 : 0,
      color: badge.unlocked ? Colors.white : Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: badge.unlocked ? AppColors.purple.withOpacity(0.3) : Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showBadgeDetail(badge),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: badge.unlocked ? AppColors.purple.withOpacity(0.15) : Colors.grey.shade300,
                    ),
                    child: Icon(
                      _iconFor(badge.iconKey),
                      color: badge.unlocked ? AppColors.purple : Colors.grey.shade500,
                      size: 28,
                    ),
                  ),
                  if (!badge.unlocked)
                    const Positioned(
                      bottom: -2,
                      right: -2,
                      child: Icon(Icons.lock_rounded, size: 18, color: Colors.grey),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                badge.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: badge.unlocked ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                badge.unlocked ? 'Unlocked' : 'Locked',
                style: TextStyle(
                  fontSize: 10,
                  color: badge.unlocked ? AppColors.green : Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBadgeDetail(BadgeModel badge) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: badge.unlocked ? AppColors.purple.withOpacity(0.15) : Colors.grey.shade300,
              ),
              child: Icon(_iconFor(badge.iconKey), color: badge.unlocked ? AppColors.purple : Colors.grey.shade500, size: 36),
            ),
            const SizedBox(height: 16),
            Text(badge.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(badge.description, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            if (badge.unlocked && badge.earnedAt != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  'Earned on ${badge.earnedAt!.day}/${badge.earnedAt!.month}/${badge.earnedAt!.year}',
                  style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(20)),
                child: const Text('Not earned yet', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
