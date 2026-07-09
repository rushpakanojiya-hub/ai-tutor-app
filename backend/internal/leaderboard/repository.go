package leaderboard

import (
	"database/sql"
	"strconv"
	"time"
)

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// GetOverall ranks by each student's all-time running totals
// (student_xp_totals) - students with zero XP simply have no row there
// and won't appear, which is expected for an "overall" ranking.
func (r *Repository) GetOverall(class, section *string) ([]Entry, error) {
	query := `
		SELECT u.id, u.name, COALESCE(u.class, ''), COALESCE(u.section, ''),
		       t.total_xp, t.total_points
		FROM student_xp_totals t
		JOIN users u ON u.id = t.student_id
		WHERE u.role = 'student'`
	args := []interface{}{}
	argN := 1

	if class != nil && *class != "" {
		query += ` AND u.class = $` + strconv.Itoa(argN)
		args = append(args, *class)
		argN++
	}
	if section != nil && *section != "" {
		query += ` AND u.section = $` + strconv.Itoa(argN)
		args = append(args, *section)
		argN++
	}
	query += ` ORDER BY t.total_xp DESC, t.total_points DESC`

	return r.queryEntries(query, args...)
}

// GetTimeScoped ranks by XP/points earned since a given time - summed
// live from the xp_events ledger (that's exactly why it's an append-only
// ledger with timestamps, not just a running total).
func (r *Repository) GetTimeScoped(since time.Time, class, section *string) ([]Entry, error) {
	query := `
		SELECT u.id, u.name, COALESCE(u.class, ''), COALESCE(u.section, ''),
		       COALESCE(SUM(e.xp_amount), 0), COALESCE(SUM(e.points_amount), 0)
		FROM xp_events e
		JOIN users u ON u.id = e.student_id
		WHERE u.role = 'student' AND e.created_at >= $1`
	args := []interface{}{since}
	argN := 2

	if class != nil && *class != "" {
		query += ` AND u.class = $` + strconv.Itoa(argN)
		args = append(args, *class)
		argN++
	}
	if section != nil && *section != "" {
		query += ` AND u.section = $` + strconv.Itoa(argN)
		args = append(args, *section)
		argN++
	}
	query += ` GROUP BY u.id, u.name, u.class, u.section ORDER BY 5 DESC, 6 DESC`

	return r.queryEntries(query, args...)
}

func (r *Repository) queryEntries(query string, args ...interface{}) ([]Entry, error) {
	rows, err := r.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Entry
	rank := 1
	for rows.Next() {
		var e Entry
		if err := rows.Scan(&e.StudentID, &e.StudentName, &e.Class, &e.Section, &e.TotalXP, &e.TotalPoints); err != nil {
			return nil, err
		}
		e.Rank = rank
		rank++
		result = append(result, e)
	}
	return result, rows.Err()
}
