import '../core/constants/api_constants.dart';
import 'api_service.dart';

class HeatmapDayModel {
  final String date;
  final bool active;
  HeatmapDayModel({required this.date, required this.active});

  factory HeatmapDayModel.fromJson(Map<String, dynamic> json) {
    return HeatmapDayModel(date: json['date'] as String? ?? '', active: json['active'] as bool? ?? false);
  }
}

class StreakSummary {
  final int currentStreak;
  final int longestStreak;
  final int activeDaysThisWeek;
  final List<bool> weeklyActivity;
  final List<HeatmapDayModel> heatmap;

  StreakSummary({
    required this.currentStreak,
    required this.longestStreak,
    required this.activeDaysThisWeek,
    required this.weeklyActivity,
    required this.heatmap,
  });

  factory StreakSummary.fromJson(Map<String, dynamic> json) {
    return StreakSummary(
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      activeDaysThisWeek: json['active_days_this_week'] as int? ?? 0,
      weeklyActivity: (json['weekly_activity'] as List<dynamic>? ?? []).map((e) => e as bool).toList(),
      heatmap: (json['heatmap'] as List<dynamic>? ?? [])
          .map((e) => HeatmapDayModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Talks to /api/streak - a real streak computed from actual activity
/// (lesson completions, quiz attempts, AI Tutor chats), never a fake number.
class StreakService {
  final ApiService _api = ApiService();

  Future<StreakSummary> fetchSummary() async {
    final response = await _api.get(ApiConstants.streak);
    return StreakSummary.fromJson(response['data'] as Map<String, dynamic>);
  }
}
