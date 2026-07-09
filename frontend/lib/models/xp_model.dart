class XPSummary {
  final int totalXP;
  final int totalPoints;
  final int level;
  final int xpIntoLevel;
  final int xpToNextLevel;
  final double progressFraction;

  XPSummary({
    required this.totalXP,
    required this.totalPoints,
    required this.level,
    required this.xpIntoLevel,
    required this.xpToNextLevel,
    required this.progressFraction,
  });

  factory XPSummary.fromJson(Map<String, dynamic> json) {
    return XPSummary(
      totalXP: json['total_xp'] as int? ?? 0,
      totalPoints: json['total_points'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      xpIntoLevel: json['xp_into_level'] as int? ?? 0,
      xpToNextLevel: json['xp_to_next_level'] as int? ?? 100,
      progressFraction: (json['progress_fraction'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
