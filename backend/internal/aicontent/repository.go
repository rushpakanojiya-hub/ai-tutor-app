package aicontent

import (
	"database/sql"
	"errors"
)

// ErrNotFound is returned when a lesson has no AI content generated yet.
var ErrNotFound = errors.New("ai content not found for this lesson")

// Repository handles direct SQL access for lesson_ai_content.
type Repository struct {
	db *sql.DB
}

// NewRepository builds an aicontent Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

const selectColumns = `id, lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json, generated_at`

// FindByLessonID returns the AI content for a lesson, or ErrNotFound if
// none has been generated for it (older lessons may not have any yet Ã¢â‚¬â€
// the Flutter side shows "AI content not available yet" in that case
// rather than an error).
func (r *Repository) FindByLessonID(lessonID int) (*AIContent, error) {
	query := `SELECT ` + selectColumns + ` FROM lesson_ai_content WHERE lesson_id = $1`

	var raw rawAIContent
	err := r.db.QueryRow(query, lessonID).Scan(
		&raw.ID, &raw.LessonID, &raw.Explanation, &raw.Summary,
		&raw.KeyPoints, &raw.Examples, &raw.PracticeQuestions, &raw.QuizJSON, &raw.GeneratedAt,
	)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return raw.toAIContent()
}

// SearchByText does a case-insensitive partial match against explanation
// and summary, returning the matching lesson_ids Ã¢â‚¬â€ used by the global
// search endpoint (Feature 6, extended per this request to search AI content).
func (r *Repository) SearchByText(query string) ([]int, error) {
	rows, err := r.db.Query(
		`SELECT lesson_id FROM lesson_ai_content WHERE explanation ILIKE '%' || $1 || '%' OR summary ILIKE '%' || $1 || '%'`,
		query,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	// BUG FIX: was missing a rows.Err() check - a connection error mid-
	// iteration would silently truncate search results instead of
	// surfacing as an error.
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return ids, nil
}
