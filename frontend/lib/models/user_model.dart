/// Plain data model for the logged-in user, shared across providers/screens.
class UserModel {
  final int id;
  final String name;
  final String role;

  UserModel({required this.id, required this.name, required this.role});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      name: json['name'] as String,
      role: json['role'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
      };
}