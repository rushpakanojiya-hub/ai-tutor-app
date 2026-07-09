class BadgeModel {
  final String key;
  final String name;
  final String description;
  final String iconKey;
  final bool unlocked;
  final DateTime? earnedAt;

  BadgeModel({
    required this.key,
    required this.name,
    required this.description,
    required this.iconKey,
    required this.unlocked,
    this.earnedAt,
  });

  factory BadgeModel.fromJson(Map<String, dynamic> json) {
    return BadgeModel(
      key: json['key'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      iconKey: json['icon_key'] as String,
      unlocked: json['unlocked'] as bool? ?? false,
      earnedAt: json['earned_at'] != null ? DateTime.tryParse(json['earned_at'] as String) : null,
    );
  }
}
