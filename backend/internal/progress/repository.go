package progress

import "database/sql"

// Repository handles direct SQL access for lesson_progress.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a progress Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// MarkComplete records that userID has completed lessonID, optionally with
// a quiz score (0-100). Calling this again for the same (user, lesson)
// pair refreshes completed_at/score instead of erroring â€” re-watching a
// lesson or retaking its quiz keeps the latest result.
func (r *Repository) MarkComplete(userID, lessonID int, score *int) error {
	query := `
		INSERT INTO lesson_progress (user_id, lesson_id, completed_at, score)
		VALUES ($1, $2, NOW(), $3)
		ON CONFLICT (user_id, lesson_id)
		DO UPDATE SET completed_at = NOW(), score = COALESCE($3, lesson_progress.score)
	`
	_, err := r.db.Exec(query, userID, lessonID, score)
	return err
}

// GetSubjectProgress returns the total lesson count for a subject, the
// count and IDs of lessons userID has completed within it.
func (r *Repository) GetSubjectProgress(userID, subjectID int) (*SubjectProgress, error) {
	sp := &SubjectProgress{SubjectID: subjectID}

	err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons WHERE subject_id = $1`, subjectID).Scan(&sp.TotalLessons)
	if err != nil {
		return nil, err
	}

	rows, err := r.db.Query(`
		SELECT l.id
		FROM lessons l
		JOIN lesson_progress lp ON lp.lesson_id = l.id AND lp.user_id = $1
		WHERE l.subject_id = $2
	`, userID, subjectID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		sp.CompletedLessonIDs = append(sp.CompletedLessonIDs, id)
	}
	sp.CompletedLessons = len(sp.CompletedLessonIDs)

	if sp.TotalLessons > 0 {
		sp.Percentage = float64(sp.CompletedLessons) / float64(sp.TotalLessons)
	}

	return sp, nil
}
