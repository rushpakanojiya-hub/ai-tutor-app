import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/xp_model.dart';
import '../../services/xp_service.dart';

/// XP progress bar for the student dashboard - self-contained (fetches
/// its own data), so it can just be dropped into the dashboard's widget
/// tree without touching any other logic.
class XPProgressCard extends StatefulWidget {
  const XPProgressCard({super.key});

  @override
  State<XPProgressCard> createState() => _XPProgressCardState();
}

class _XPProgressCardState extends State<XPProgressCard> {
  final XPService _xpService = XPService();
  XPSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final summary = await _xpService.fetchMine();
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      // Silent - this is a dashboard widget, not worth an error banner.
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.purple, AppColors.purple.withOpacity(0.75)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text('Level ${summary.level}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text('${summary.totalPoints} pts', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: summary.progressFraction.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${summary.xpIntoLevel} / 100 XP \u2022 ${summary.xpToNextLevel} XP to Level ${summary.level + 1}',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
