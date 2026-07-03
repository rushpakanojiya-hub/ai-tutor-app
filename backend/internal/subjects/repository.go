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

// baseSelect joins in a lesson count so every read path returns LessonCount
// without the caller needing a second query per subject.
const baseSelect = `
	SELECT s.id, s.category_id, s.name, s.description, s.thumbnail, s.created_at,
	       COUNT(l.id) AS lesson_count
	FROM subjects s
	LEFT JOIN lessons l ON l.subject_id = s.id
`

func scanSubject(row interface{ Scan(...any) error }) (Subject, error) {
	var s Subject
	var description, thumbnail sql.NullString
	err := row.Scan(&s.ID, &s.CategoryID, &s.Name, &description, &thumbnail, &s.CreatedAt, &s.LessonCount)
	s.Description = description.String
	s.Thumbnail = thumbnail.String
	return s, err
}

// FindAll returns every subject across all categories.
func (r *Repository) FindAll() ([]Subject, error) {
	query := baseSelect + ` GROUP BY s.id ORDER BY s.name`
	rows, err := r.db.Query(query)
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
func (r *Repository) FindByCategoryID(categoryID int) ([]Subject, error) {
	query := baseSelect + ` WHERE s.category_id = $1 GROUP BY s.id ORDER BY s.name`
	rows, err := r.db.Query(query, categoryID)
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
func (r *Repository) FindByID(id int) (*Subject, error) {
	query := baseSelect + ` WHERE s.id = $1 GROUP BY s.id`
	row := r.db.QueryRow(query, id)
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
func (r *Repository) SearchByName(query string) ([]Subject, error) {
	sqlQuery := baseSelect + ` WHERE s.name ILIKE '%' || $1 || '%' GROUP BY s.id ORDER BY s.name`
	rows, err := r.db.Query(sqlQuery, query)
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