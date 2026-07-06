import '../core/constants/api_constants.dart';
import 'api_service.dart';

class StreakSummary {
  final int currentStreak;
  final int activeDaysThisWeek;

  StreakSummary({required this.currentStreak, required this.activeDaysThisWeek});

  factory StreakSummary.fromJson(Map<String, dynamic> json) {
    return StreakSummary(
      currentStreak: json['current_streak'] as int? ?? 0,
      activeDaysThisWeek: json['active_days_this_week'] as int? ?? 0,
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
