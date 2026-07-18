package admin

import (
	"database/sql"

	"ai-tutor-backend/internal/streak"
)

// Repository runs simple, direct COUNT queries against existing tables -
// no new tables needed for this dashboard.
type Repository struct {
	db *sql.DB
	// Student Progress Overview (additive) - reuses streak's existing
	// "consecutive active days" logic instead of duplicating the
	// date-diff calculation here.
	streakRepo *streak.Repository
}

func NewRepository(db *sql.DB, streakRepo *streak.Repository) *Repository {
	return &Repository{db: db, streakRepo: streakRepo}
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

// --- Student Progress Overview (additive) ---

// ListStudentProgress returns one row per student with lessons
// completed, average quiz score, and current streak.
func (r *Repository) ListStudentProgress() ([]StudentProgress, error) {
	var totalLessons int
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons`).Scan(&totalLessons); err != nil {
		return nil, err
	}

	rows, err := r.db.Query(`
		SELECT
			u.id, u.name, u.email,
			COALESCE(u.class, ''), COALESCE(u.section, ''),
			(SELECT COUNT(DISTINCT lp.lesson_id) FROM lesson_progress lp WHERE lp.user_id = u.id),
			(SELECT AVG(qa.score_percent) FROM quiz_attempts qa WHERE qa.user_id = u.id)
		FROM users u
		WHERE u.role = 'student'
		ORDER BY u.name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []StudentProgress
	for rows.Next() {
		var sp StudentProgress
		var avgScore sql.NullFloat64
		if err := rows.Scan(&sp.UserID, &sp.Name, &sp.Email, &sp.Class, &sp.Section, &sp.LessonsCompleted, &avgScore); err != nil {
			return nil, err
		}
		sp.TotalLessons = totalLessons
		if totalLessons > 0 {
			sp.CompletionPercent = float64(sp.LessonsCompleted) / float64(totalLessons)
		}
		if avgScore.Valid {
			v := avgScore.Float64
			sp.AverageQuizScore = &v
		}
		streakCount, err := r.streakRepo.GetCurrentStreak(sp.UserID)
		if err != nil {
			return nil, err
		}
		sp.CurrentStreak = streakCount
		result = append(result, sp)
	}
	return result, rows.Err()
}