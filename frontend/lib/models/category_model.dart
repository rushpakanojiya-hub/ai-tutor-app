/// Plain data model for a course category (e.g. "Academic", "Programming").
class CategoryModel {
  final int id;
  final String name;
  final String icon;

  CategoryModel({required this.id, required this.name, required this.icon});

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
    );
  }
}
