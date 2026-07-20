// Package streak computes a real "Learning Streak" from actual student
// activity (lesson completions, quiz attempts, AI Tutor chats) - no
// fabricated numbers. Any of those three actions marks "today" as active
// for that user.
package streak

import (
	"database/sql"
	"log"
	"time"
)

// BUG FIX (timezone mismatch - audit-flagged, highest-risk file):
// every "today"/"this week"/"last N days" calculation here used to mix
// two different, independently-configured clocks: Go's time.Now()
// (whatever timezone the app process's container happens to be running
// in - typically UTC by default) on one side, and Postgres's CURRENT_DATE
// (whatever timezone the DB session happens to be configured with) on
// the other. If those two didn't agree - or either one didn't match this
// app's actual (India-based) users - "today" could disagree by hours,
// breaking streak continuity right around midnight and giving a wrong
// current/longest streak or a weekly activity graph shifted by a day.
// istLocation makes the timezone explicit and identical on both the Go
// side (todayIST) and the SQL side (the "AT TIME ZONE 'Asia/Kolkata'"
// queries below), so the two can never silently disagree again. If your
// users are in a different timezone, change both consistently.
var istLocation = mustLoadIST()

func mustLoadIST() *time.Location {
	loc, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("[streak] failed to load Asia/Kolkata timezone, falling back to UTC: %v", err)
		return time.UTC
	}
	return loc
}

// todayIST returns today's date (midnight) in the app's canonical
// timezone, replacing the previous ambient time.Now() calls.
func todayIST() time.Time {
	return truncateToDate(time.Now().In(istLocation))
}

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// RecordActivity marks today (in IST) as an active day for userID.
// Idempotent - safe to call many times in the same day.
func (r *Repository) RecordActivity(userID int) error {
	_, err := r.db.Exec(`
		INSERT INTO user_activity_days (user_id, activity_date)
		VALUES ($1, (now() AT TIME ZONE 'Asia/Kolkata')::date)
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

	today := todayIST()
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
// been active since the start of the current calendar week (IST).
func (r *Repository) GetActiveDaysThisWeek(userID int) (int, error) {
	var count int
	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= date_trunc('week', (now() AT TIME ZONE 'Asia/Kolkata')::date)`, userID,
	).Scan(&count)
	return count, err
}

// GetWeeklyActivity returns a 7-element bool array for the last 7 days
// (oldest first, today last), true if the user was active that day - for
// the "weekly streak graph".
func (r *Repository) GetWeeklyActivity(userID int) ([]bool, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= (now() AT TIME ZONE 'Asia/Kolkata')::date - INTERVAL '6 days'`, userID)
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
	if err := rows.Err(); err != nil {
		return nil, err
	}

	result := make([]bool, 7)
	today := todayIST()
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
		WHERE user_id = $1 AND activity_date >= (now() AT TIME ZONE 'Asia/Kolkata')::date - ($2 || ' days')::interval`, userID, days-1)
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
	if err := rows.Err(); err != nil {
		return nil, err
	}

	today := todayIST()
	result := make([]HeatmapDay, days)
	for i := 0; i < days; i++ {
		day := today.AddDate(0, 0, -(days-1)+i)
		key := day.Format("2006-01-02")
		result[i] = HeatmapDay{Date: key, Active: activeDates[key]}
	}
	return result, nil
}

// --- Learning Calendar month view (additive) ---
//
// Unlike GetActivityHeatmap (a rolling "last N days" window that always
// ends today), this returns every active date within one specific
// calendar month - regardless of month/year - so the Learning Calendar
// screen can page back through past months' full history.
func (r *Repository) GetActiveDatesForMonth(userID, year, month int) ([]string, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1
			AND activity_date >= make_date($2, $3, 1)
			AND activity_date < (make_date($2, $3, 1) + INTERVAL '1 month')`,
		userID, year, month)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var dates []string
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		dates = append(dates, d.Format("2006-01-02"))
	}
	return dates, rows.Err()
}

func truncateToDate(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}

// GetCurrentStreakWithStartDate is like GetCurrentStreak, but also
// returns the date the current unbroken run started. Added (additive -
// GetCurrentStreak itself is untouched, so no other caller is affected)
// for the "study streak reward logic" QA fix in xp/service.go: without
// a stable per-run anchor, a milestone reward's dedup key ("streak-
// milestone-1") stayed the same forever, so a student who broke their
// streak and later built a fresh 7-day run again could never be
// rewarded for it a second time - the run's start date makes each
// distinct streak run's key unique.
func (r *Repository) GetCurrentStreakWithStartDate(userID int) (int, time.Time, error) {
	dates, err := r.allDatesDesc(userID)
	if err != nil {
		return 0, time.Time{}, err
	}
	if len(dates) == 0 {
		return 0, time.Time{}, nil
	}

	today := todayIST()
	daysSinceRecent := int(today.Sub(dates[0]).Hours() / 24)
	if daysSinceRecent > 1 {
		return 0, time.Time{}, nil
	}

	streakCount := 1
	startDate := dates[0]
	for i := 1; i < len(dates); i++ {
		diff := int(dates[i-1].Sub(dates[i]).Hours() / 24)
		if diff == 1 {
			streakCount++
			startDate = dates[i]
		} else {
			break
		}
	}
	return streakCount, startDate, nil
}
