/// Real, admin-only platform-wide counts. Every field comes from a COUNT
/// query on existing tables - nothing here is estimated.
class AdminDashboardStats {
  final int totalStudents;
  final int totalTeachers;
  final int pendingTeachers;
  final int totalSubjects;
  final int totalLessons;
  final int totalQuizAttempts;
  final int totalAiChatSessions;
  final int newRegistrationsThisWeek;

  AdminDashboardStats({
    required this.totalStudents,
    required this.totalTeachers,
    required this.pendingTeachers,
    required this.totalSubjects,
    required this.totalLessons,
    required this.totalQuizAttempts,
    required this.totalAiChatSessions,
    required this.newRegistrationsThisWeek,
  });

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    return AdminDashboardStats(
      totalStudents: json['total_students'] as int? ?? 0,
      totalTeachers: json['total_teachers'] as int? ?? 0,
      pendingTeachers: json['pending_teachers'] as int? ?? 0,
      totalSubjects: json['total_subjects'] as int? ?? 0,
      totalLessons: json['total_lessons'] as int? ?? 0,
      totalQuizAttempts: json['total_quiz_attempts'] as int? ?? 0,
      totalAiChatSessions: json['total_ai_chat_sessions'] as int? ?? 0,
      newRegistrationsThisWeek: json['new_registrations_this_week'] as int? ?? 0,
    );
  }
}

/// One teacher application in the admin review queue.
class TeacherApplicationModel {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String qualification;
  final String experience;
  final String subjects;
  final String bio;
  final String status;
  final DateTime createdAt;

  TeacherApplicationModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.qualification,
    required this.experience,
    required this.subjects,
    required this.bio,
    required this.status,
    required this.createdAt,
  });

  factory TeacherApplicationModel.fromJson(Map<String, dynamic> json) {
    return TeacherApplicationModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      qualification: json['qualification'] as String? ?? '',
      experience: json['experience'] as String? ?? '',
      subjects: json['subjects'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
