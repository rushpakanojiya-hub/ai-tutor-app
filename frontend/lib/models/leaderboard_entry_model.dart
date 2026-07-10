class LeaderboardEntry {
  final int rank;
  final int studentId;
  final String studentName;
  final String classValue;
  final String section;
  final int totalXP;
  final int totalPoints;
  final bool isCurrentUser;

  LeaderboardEntry({
    required this.rank,
    required this.studentId,
    required this.studentName,
    required this.classValue,
    required this.section,
    required this.totalXP,
    required this.totalPoints,
    required this.isCurrentUser,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: json['rank'] as int? ?? 0,
      studentId: json['student_id'] as int? ?? 0,
      studentName: json['student_name'] as String? ?? '',
      classValue: json['class'] as String? ?? '',
      section: json['section'] as String? ?? '',
      totalXP: json['total_xp'] as int? ?? 0,
      totalPoints: json['total_points'] as int? ?? 0,
      isCurrentUser: json['is_current_user'] as bool? ?? false,
    );
  }
}
