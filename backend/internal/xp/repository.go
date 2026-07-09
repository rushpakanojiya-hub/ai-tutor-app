package xp

import "database/sql"

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// GetTotals returns the student's current running totals (0,0 if they
// have no row yet - they simply haven't earned anything).
func (r *Repository) GetTotals(studentID int) (int, int, error) {
	var xpTotal, pointsTotal int
	err := r.db.QueryRow(`SELECT total_xp, total_points FROM student_xp_totals WHERE student_id = $1`, studentID).Scan(&xpTotal, &pointsTotal)
	if err == sql.ErrNoRows {
		return 0, 0, nil
	}
	return xpTotal, pointsTotal, err
}

// AwardXP records one XP event and bumps the running totals - but only
// if this exact (student, activityType, referenceKey) hasn't already
// been awarded (the UNIQUE constraint on xp_events makes this safe to
// call repeatedly/concurrently without double-counting, e.g. if a
// student's course-completion check fires from two different hooks).
func (r *Repository) AwardXP(studentID int, activityType, referenceKey string, xpAmount, pointsAmount int) error {
	res, err := r.db.Exec(`
		INSERT INTO xp_events (student_id, activity_type, reference_key, xp_amount, points_amount)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (student_id, activity_type, reference_key) DO NOTHING`,
		studentID, activityType, referenceKey, xpAmount, pointsAmount)
	if err != nil {
		return err
	}
	rows, err := res.RowsAffected()
	if err != nil || rows == 0 {
		return err // either an error, or a no-op duplicate - nothing to add to totals
	}

	_, err = r.db.Exec(`
		INSERT INTO student_xp_totals (student_id, total_xp, total_points, updated_at)
		VALUES ($1, $2, $3, now())
		ON CONFLICT (student_id) DO UPDATE SET
			total_xp = student_xp_totals.total_xp + $2,
			total_points = student_xp_totals.total_points + $3,
			updated_at = now()`,
		studentID, xpAmount, pointsAmount)
	return err
}

// IsSubjectFullyCompleted checks if the student has completed every
// lesson in the given subject (independent lightweight query - does not
// depend on the badge package, per the "don't touch badges" instruction).
func (r *Repository) IsSubjectFullyCompleted(studentID, subjectID int) (bool, error) {
	var totalLessons, completedLessons int
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons WHERE subject_id = $1`, subjectID).Scan(&totalLessons); err != nil {
		return false, err
	}
	if totalLessons == 0 {
		return false, nil
	}
	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM lesson_progress lp
		JOIN lessons l ON l.id = lp.lesson_id
		WHERE l.subject_id = $1 AND lp.user_id = $2`, subjectID, studentID).Scan(&completedLessons)
	if err != nil {
		return false, err
	}
	return completedLessons == totalLessons, nil
}
