// Package streak computes a real "Learning Streak" from actual student
// activity (lesson completions, quiz attempts, AI Tutor chats) - no
// fabricated numbers. Any of those three actions marks "today" as active
// for that user.
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

func (r *Repository) allDatesDesc(userID int) ([]time.Time, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1
		ORDER BY activity_date DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var dates []time.Time
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		dates = append(dates, d)
	}
	return dates, rows.Err()
}

// GetCurrentStreak returns the number of consecutive active days ending
// today or yesterday. Returns 0 if the most recent activity was more
// than 1 day ago (streak broken).
func (r *Repository) GetCurrentStreak(userID int) (int, error) {
	dates, err := r.allDatesDesc(userID)
	if err != nil {
		return 0, err
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

// GetLongestStreak scans the user's full activity history for the
// longest run of consecutive active days ever, not just the current one.
func (r *Repository) GetLongestStreak(userID int) (int, error) {
	dates, err := r.allDatesDesc(userID)
	if err != nil {
		return 0, err
	}
	if len(dates) == 0 {
		return 0, nil
	}

	longest := 1
	current := 1
	for i := 1; i < len(dates); i++ {
		diff := int(dates[i-1].Sub(dates[i]).Hours() / 24)
		if diff == 1 {
			current++
			if current > longest {
				longest = current
			}
		} else {
			current = 1
		}
	}
	return longest, nil
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

// GetWeeklyActivity returns a 7-element bool array for the last 7 days
// (oldest first, today last), true if the user was active that day - for
// the "weekly streak graph".
func (r *Repository) GetWeeklyActivity(userID int) ([]bool, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= CURRENT_DATE - INTERVAL '6 days'`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	activeDates := map[string]bool{}
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		activeDates[d.Format("2006-01-02")] = true
	}

	result := make([]bool, 7)
	today := truncateToDate(time.Now())
	for i := 0; i < 7; i++ {
		day := today.AddDate(0, 0, -6+i)
		result[i] = activeDates[day.Format("2006-01-02")]
	}
	return result, nil
}

// GetActivityHeatmap returns one entry per day for the last `days` days
// (oldest first), for a GitHub-style learning calendar.
func (r *Repository) GetActivityHeatmap(userID, days int) ([]HeatmapDay, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= CURRENT_DATE - ($2 || ' days')::interval`, userID, days-1)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	activeDates := map[string]bool{}
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		activeDates[d.Format("2006-01-02")] = true
	}

	today := truncateToDate(time.Now())
	result := make([]HeatmapDay, days)
	for i := 0; i < days; i++ {
		day := today.AddDate(0, 0, -(days-1)+i)
		key := day.Format("2006-01-02")
		result[i] = HeatmapDay{Date: key, Active: activeDates[key]}
	}
	return result, nil
}

func truncateToDate(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}
