class StudentClassSectionModel {
  final int id;
  final String name;
  final String email;
  final String classValue;
  final String section;

  StudentClassSectionModel({
    required this.id,
    required this.name,
    required this.email,
    required this.classValue,
    required this.section,
  });

  factory StudentClassSectionModel.fromJson(Map<String, dynamic> json) {
    return StudentClassSectionModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      classValue: json['class'] as String? ?? '',
      section: json['section'] as String? ?? '',
    );
  }
}
