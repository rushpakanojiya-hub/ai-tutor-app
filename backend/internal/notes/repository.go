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

// --- Lesson Resource Management (additive) ---
//
// The admin/teacher "PDF Notes" upload in Lesson Resource Management
// needs to show up in the existing student-facing notes list (the
// NotesWidget reads from this same "notes" table via ListByLesson), so
// these let the lessons package keep exactly one note in sync with a
// lesson's pdf_url without duplicating the notes UI/table.

// FindFirstByLessonID returns the first note for a lesson, or nil if none.
func (r *Repository) FindFirstByLessonID(lessonID int) (*Note, error) {
	var n Note
	query := `SELECT id, lesson_id, title, pdf_url, created_at FROM notes WHERE lesson_id = $1 ORDER BY id LIMIT 1`
	err := r.db.QueryRow(query, lessonID).Scan(&n.ID, &n.LessonID, &n.Title, &n.PDFURL, &n.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &n, nil
}

func (r *Repository) Update(id int, title, pdfURL string) error {
	res, err := r.db.Exec(`UPDATE notes SET title = $1, pdf_url = $2 WHERE id = $3`, title, pdfURL, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrNoteNotFound
	}
	return nil
}

func (r *Repository) Delete(id int) error {
	res, err := r.db.Exec(`DELETE FROM notes WHERE id = $1`, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrNoteNotFound
	}
	return nil
}

// FindByID returns a single note by id, or ErrNoteNotFound if none.
func (r *Repository) FindByID(id int) (*Note, error) {
	var n Note
	query := `SELECT id, lesson_id, title, pdf_url, created_at FROM notes WHERE id = $1`
	err := r.db.QueryRow(query, id).Scan(&n.ID, &n.LessonID, &n.Title, &n.PDFURL, &n.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrNoteNotFound
	}
	if err != nil {
		return nil, err
	}
	return &n, nil
}