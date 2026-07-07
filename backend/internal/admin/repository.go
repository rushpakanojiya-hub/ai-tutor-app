package admin

import "database/sql"

// Repository runs simple, direct COUNT queries against existing tables -
// no new tables needed for this dashboard.
type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) GetDashboardStats() (*DashboardStats, error) {
	stats := &DashboardStats{}

	if err := r.db.QueryRow(`SELECT COUNT(*) FROM users WHERE role = 'student'`).Scan(&stats.TotalStudents); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM users WHERE role = 'teacher' AND status = 'active'`).Scan(&stats.TotalTeachers); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM users WHERE role = 'teacher' AND status = 'pending'`).Scan(&stats.PendingTeachers); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM subjects`).Scan(&stats.TotalSubjects); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons`).Scan(&stats.TotalLessons); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM quiz_attempts`).Scan(&stats.TotalQuizAttempts); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM ai_chat_sessions`).Scan(&stats.TotalAiChatSessions); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '7 days'`).Scan(&stats.NewRegistrationsThisWeek); err != nil {
		return nil, err
	}

	return stats, nil
}
