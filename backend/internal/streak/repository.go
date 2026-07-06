// Package streak computes a real "Learning Streak" from actual student
// activity (lesson completions, quiz attempts, AI Tutor chats) - no
// fabricated numbers. Any of those three actions marks "today" as active
// for that user; the streak is the count of consecutive active days
// ending today or yesterday (a streak isn't broken until a full day
// passes with zero activity).
package streak

import (
	"database/sql"
	"time"
)

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// RecordActivity marks today as an active day for userID. Idempotent -
// safe to call many times in the same day.
func (r *Repository) RecordActivity(userID int) error {
	_, err := r.db.Exec(`
		INSERT INTO user_activity_days (user_id, activity_date)
		VALUES ($1, CURRENT_DATE)
		ON CONFLICT (user_id, activity_date) DO NOTHING`, userID)
	return err
}

// GetCurrentStreak returns the number of consecutive active days ending
// today or yesterday. Returns 0 if the most recent activity was more
// than 1 day ago (streak broken).
func (r *Repository) GetCurrentStreak(userID int) (int, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1
		ORDER BY activity_date DESC`, userID)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	var dates []time.Time
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return 0, err
		}
		dates = append(dates, d)
	}
	if len(dates) == 0 {
		return 0, nil
	}

	today := truncateToDate(time.Now())
	daysSinceRecent := int(today.Sub(dates[0]).Hours() / 24)
	if daysSinceRecent > 1 {
		return 0, nil
	}

	streakCount := 1
	for i := 1; i < len(dates); i++ {
		diff := int(dates[i-1].Sub(dates[i]).Hours() / 24)
		if diff == 1 {
			streakCount++
		} else {
			break
		}
	}
	return streakCount, nil
}

// GetActiveDaysThisWeek returns how many distinct days (0-7) the user has
// been active since the start of the current calendar week.
func (r *Repository) GetActiveDaysThisWeek(userID int) (int, error) {
	var count int
	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= date_trunc('week', CURRENT_DATE)`, userID,
	).Scan(&count)
	return count, err
}

func truncateToDate(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}
