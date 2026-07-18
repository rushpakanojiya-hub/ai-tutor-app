// Package admin implements the admin-only dashboard: real platform-wide
// counts (students, teachers, subjects, lessons, quiz attempts, AI chats)
// computed directly from existing tables. Teacher application review
// reuses the endpoints already built in internal/auth
// (/api/auth/admin/teachers/*) - this package doesn't duplicate that.
package admin

// DashboardStats is the response for GET /api/admin/dashboard. Every
// field is a real COUNT query - nothing here is estimated or fabricated.
type DashboardStats struct {
	TotalStudents      int `json:"total_students"`
	TotalTeachers      int `json:"total_teachers"`       // active teachers only
	PendingTeachers    int `json:"pending_teachers"`
	TotalSubjects      int `json:"total_subjects"`        // closest equivalent to "courses" in this app's data model
	TotalLessons       int `json:"total_lessons"`
	TotalQuizAttempts  int `json:"total_quiz_attempts"`
	TotalAiChatSessions int `json:"total_ai_chat_sessions"`
	NewRegistrationsThisWeek int `json:"new_registrations_this_week"`
}

// --- Student Progress Overview (additive) ---
//
// One row per student for the admin-only "Student Progress" screen -
// lessons completed (count + percentage of everything on the
// platform), average quiz score, and current learning streak. All
// computed directly from existing tables (lesson_progress,
// quiz_attempts, user_activity_days), same "no fabricated numbers"
// approach as DashboardStats above.
type StudentProgress struct {
	UserID            int      `json:"user_id"`
	Name              string   `json:"name"`
	Email             string   `json:"email"`
	Class             string   `json:"class"`
	Section           string   `json:"section"`
	LessonsCompleted  int      `json:"lessons_completed"`
	TotalLessons      int      `json:"total_lessons"`
	CompletionPercent float64  `json:"completion_percent"` // 0.0 - 1.0
	AverageQuizScore  *float64 `json:"average_quiz_score"` // null if the student has no quiz attempts yet
	CurrentStreak     int      `json:"current_streak"`
}