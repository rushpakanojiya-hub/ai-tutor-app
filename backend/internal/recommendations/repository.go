package recommendations

import "database/sql"

// Repository handles direct SQL access for recommendations, plus the
// underlying query that computes the "next not-yet-completed lesson per
// subject" rule described in model.go.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a recommendations Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// ComputeAndStore recomputes this user's recommendations from their
// current progress and (re)persists them to the "recommendations" table,
// then returns the fresh list. Called on every GET so recommendations
// always reflect the latest completed lessons â€” simpler than trying to
// incrementally maintain the table.
func (r *Repository) ComputeAndStore(userID int) ([]Recommendation, error) {
	// For every subject where the user has completed at least one lesson,
	// find the lowest order_number lesson in that subject that they have
	// NOT completed yet â€” that's the "next" recommendation. The most
	// recently completed lesson in that subject becomes the "lesson_id"
	// (why this was recommended).
	query := `
		WITH completed AS (
			SELECT l.subject_id, l.id AS lesson_id, l.order_number, lp.completed_at
			FROM lesson_progress lp
			JOIN lessons l ON l.id = lp.lesson_id
			WHERE lp.user_id = $1
		),
		latest_completed_per_subject AS (
			SELECT subject_id, lesson_id, order_number,
			       ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY completed_at DESC) AS rn
			FROM completed
		),
		next_lesson AS (
			SELECT lc.subject_id, lc.lesson_id AS source_lesson_id,
			       (
			           SELECT l2.id FROM lessons l2
			           WHERE l2.subject_id = lc.subject_id
			             AND l2.id NOT IN (SELECT lesson_id FROM completed WHERE subject_id = lc.subject_id)
			           ORDER BY l2.order_number ASC
			           LIMIT 1
			       ) AS recommended_lesson_id
			FROM latest_completed_per_subject lc
			WHERE lc.rn = 1
		)
		SELECT source_lesson_id, recommended_lesson_id, subject_id
		FROM next_lesson
		WHERE recommended_lesson_id IS NOT NULL
	`

	rows, err := r.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	type pair struct {
		sourceLessonID      int
		recommendedLessonID int
		subjectID           int
	}
	var pairs []pair
	for rows.Next() {
		var p pair
		if err := rows.Scan(&p.sourceLessonID, &p.recommendedLessonID, &p.subjectID); err != nil {
			rows.Close()
			return nil, err
		}
		pairs = append(pairs, p)
	}
	rows.Close()

	// Persist: clear old recommendations for this user, insert the fresh set.
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	if _, err := tx.Exec(`DELETE FROM recommendations WHERE user_id = $1`, userID); err != nil {
		tx.Rollback()
		return nil, err
	}
	for _, p := range pairs {
		if _, err := tx.Exec(
			`INSERT INTO recommendations (user_id, lesson_id, recommended_lesson_id) VALUES ($1, $2, $3)`,
			userID, p.sourceLessonID, p.recommendedLessonID,
		); err != nil {
			tx.Rollback()
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return r.ListByUser(userID)
}

// ListByUser returns a user's stored recommendations, joined with the
// recommended lesson's title and subject for direct display.
func (r *Repository) ListByUser(userID int) ([]Recommendation, error) {
	query := `
		SELECT r.id, r.user_id, r.lesson_id, r.recommended_lesson_id, r.created_at,
		       l.title, l.subject_id, s.name
		FROM recommendations r
		JOIN lessons l ON l.id = r.recommended_lesson_id
		JOIN subjects s ON s.id = l.subject_id
		WHERE r.user_id = $1
		ORDER BY r.created_at DESC
	`
	rows, err := r.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Recommendation
	for rows.Next() {
		var rec Recommendation
		if err := rows.Scan(
			&rec.ID, &rec.UserID, &rec.LessonID, &rec.RecommendedLessonID, &rec.CreatedAt,
			&rec.RecommendedTitle, &rec.RecommendedSubjectID, &rec.SubjectName,
		); err != nil {
			return nil, err
		}
		result = append(result, rec)
	}
	return result, nil
}
