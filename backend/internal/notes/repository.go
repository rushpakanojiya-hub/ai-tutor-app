package notes

import "database/sql"

// Repository handles direct SQL access for notes.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a notes Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// FindByLessonID returns every note attached to a lesson.
func (r *Repository) FindByLessonID(lessonID int) ([]Note, error) {
	query := `SELECT id, lesson_id, title, pdf_url, created_at FROM notes WHERE lesson_id = $1 ORDER BY id`
	rows, err := r.db.Query(query, lessonID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.ID, &n.LessonID, &n.Title, &n.PDFURL, &n.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, n)
	}
	return result, nil
}

// Create inserts a new note and returns its generated ID.
func (r *Repository) Create(lessonID int, title, pdfURL string) (int, error) {
	var id int
	query := `INSERT INTO notes (lesson_id, title, pdf_url) VALUES ($1, $2, $3) RETURNING id`
	err := r.db.QueryRow(query, lessonID, title, pdfURL).Scan(&id)
	return id, err
}