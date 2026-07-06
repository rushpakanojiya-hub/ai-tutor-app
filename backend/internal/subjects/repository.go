package subjects

import (
	"database/sql"
	"errors"
)

// ErrSubjectNotFound is returned when no subject matches the given ID.
var ErrSubjectNotFound = errors.New("subject not found")

// Repository handles direct SQL access for subjects.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a subjects Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// baseSelect uses scalar subqueries (not joins) for each count/sum so rows
// are never multiplied - each subquery independently counts against its
// own table. userID drives the ProgressPercentage subquery; pass 0 for
// contexts with no signed-in user (progress will just read 0%).
const baseSelect = `
	SELECT
		s.id, s.category_id, s.name, s.description, s.thumbnail, s.difficulty, s.created_at,
		(SELECT COUNT(*) FROM lessons l WHERE l.subject_id = s.id) AS lesson_count,
		(SELECT COUNT(*) FROM notes n JOIN lessons l ON l.id = n.lesson_id WHERE l.subject_id = s.id) AS notes_count,
		(SELECT COUNT(*) FROM lesson_ai_content ac JOIN lessons l ON l.id = ac.lesson_id
			WHERE l.subject_id = s.id AND ac.quiz_json IS NOT NULL AND ac.quiz_json::text <> '[]') AS quiz_count,
		(SELECT COALESCE(SUM(l.duration), 0) FROM lessons l WHERE l.subject_id = s.id) AS total_duration_minutes,
		(SELECT COUNT(*) FROM lessons l WHERE l.subject_id = s.id) AS total_for_progress,
		(SELECT COUNT(*) FROM lessons l JOIN lesson_progress lp ON lp.lesson_id = l.id AND lp.user_id = $1
			WHERE l.subject_id = s.id) AS completed_for_progress
	FROM subjects s
`

func scanSubject(row interface{ Scan(...any) error }) (Subject, error) {
	var s Subject
	var description, thumbnail sql.NullString
	var totalDurationMinutes, totalForProgress, completedForProgress int

	err := row.Scan(
		&s.ID, &s.CategoryID, &s.Name, &description, &thumbnail, &s.Difficulty, &s.CreatedAt,
		&s.LessonCount, &s.NotesCount, &s.QuizCount,
		&totalDurationMinutes, &totalForProgress, &completedForProgress,
	)
	s.Description = description.String
	s.Thumbnail = thumbnail.String
	s.LearningHours = float64(totalDurationMinutes) / 60.0
	s.CompletedLessons = completedForProgress

	if totalForProgress > 0 {
		s.ProgressPercentage = (float64(completedForProgress) / float64(totalForProgress)) * 100
	}

	return s, err
}

// FindAll returns every subject across all categories, with progress
// computed for userID (pass 0 if there's no signed-in user in context).
func (r *Repository) FindAll(userID int) ([]Subject, error) {
	query := baseSelect + ` GROUP BY s.id ORDER BY s.name`
	rows, err := r.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Subject
	for rows.Next() {
		s, err := scanSubject(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	return result, nil
}

// FindByCategoryID returns every subject belonging to one category.
func (r *Repository) FindByCategoryID(userID, categoryID int) ([]Subject, error) {
	query := baseSelect + ` WHERE s.category_id = $2 GROUP BY s.id ORDER BY s.name`
	rows, err := r.db.Query(query, userID, categoryID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Subject
	for rows.Next() {
		s, err := scanSubject(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	return result, nil
}

// FindByID returns a single subject, or ErrSubjectNotFound.
func (r *Repository) FindByID(userID, id int) (*Subject, error) {
	query := baseSelect + ` WHERE s.id = $2 GROUP BY s.id`
	row := r.db.QueryRow(query, userID, id)
	s, err := scanSubject(row)
	if err == sql.ErrNoRows {
		return nil, ErrSubjectNotFound
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// Create inserts a new subject and returns its generated ID.
func (r *Repository) Create(categoryID int, name, description, thumbnail string) (int, error) {
	var id int
	query := `
		INSERT INTO subjects (category_id, name, description, thumbnail)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`
	err := r.db.QueryRow(query, categoryID, name, description, thumbnail).Scan(&id)
	return id, err
}

// SearchByName does a case-insensitive partial match, used by the global
// search endpoint (Feature 6).
func (r *Repository) SearchByName(userID int, query string) ([]Subject, error) {
	sqlQuery := baseSelect + ` WHERE s.name ILIKE '%' || $2 || '%' GROUP BY s.id ORDER BY s.name`
	rows, err := r.db.Query(sqlQuery, userID, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Subject
	for rows.Next() {
		s, err := scanSubject(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	return result, nil
}
