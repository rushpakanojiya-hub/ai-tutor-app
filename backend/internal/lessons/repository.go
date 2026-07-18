package lessons

import (
	"database/sql"
	"errors"
)

// ErrLessonNotFound is returned when no lesson matches the given ID.
var ErrLessonNotFound = errors.New("lesson not found")

// Repository handles direct SQL access for lessons.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a lessons Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

const selectColumns = `id, subject_id, title, description, video_url, video_source, pdf_url, pdf_title, pdf_description, assignment_url, thumbnail_url, duration, order_number, status, created_at`

func scanLesson(row interface{ Scan(...any) error }) (Lesson, error) {
	var l Lesson
	var description, videoURL, videoSource, pdfURL, pdfTitle, pdfDescription, assignmentURL, thumbnailURL sql.NullString
	err := row.Scan(&l.ID, &l.SubjectID, &l.Title, &description, &videoURL, &videoSource, &pdfURL, &pdfTitle, &pdfDescription, &assignmentURL, &thumbnailURL, &l.Duration, &l.OrderNumber, &l.Status, &l.CreatedAt)
	l.Description = description.String
	l.VideoURL = videoURL.String
	l.VideoSource = videoSource.String
	l.PDFURL = pdfURL.String
	l.PDFTitle = pdfTitle.String
	l.PDFDescription = pdfDescription.String
	l.AssignmentURL = assignmentURL.String
	l.ThumbnailURL = thumbnailURL.String
	return l, err
}

// FindBySubjectID returns every lesson for a subject, in display order.
func (r *Repository) FindBySubjectID(subjectID int) ([]Lesson, error) {
	query := `SELECT ` + selectColumns + ` FROM lessons WHERE subject_id = $1 ORDER BY order_number, id`
	rows, err := r.db.Query(query, subjectID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Lesson
	for rows.Next() {
		l, err := scanLesson(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, l)
	}
	return result, nil
}

// FindByID returns a single lesson, or ErrLessonNotFound.
func (r *Repository) FindByID(id int) (*Lesson, error) {
	query := `SELECT ` + selectColumns + ` FROM lessons WHERE id = $1`
	row := r.db.QueryRow(query, id)
	l, err := scanLesson(row)
	if err == sql.ErrNoRows {
		return nil, ErrLessonNotFound
	}
	if err != nil {
		return nil, err
	}
	return &l, nil
}

// Create inserts a new lesson and returns its generated ID.
func (r *Repository) Create(req CreateLessonRequest) (int, error) {
	var id int
	query := `
		INSERT INTO lessons (subject_id, title, description, video_url, pdf_url, thumbnail_url, duration, order_number)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id
	`
	err := r.db.QueryRow(
		query,
		req.SubjectID, req.Title, req.Description, req.VideoURL, req.PDFURL, req.ThumbnailURL, req.Duration, req.OrderNumber,
	).Scan(&id)
	return id, err
}

// SearchByTitle does a case-insensitive partial match, used by the global
// search endpoint (Feature 6).
func (r *Repository) SearchByTitle(query string) ([]Lesson, error) {
	sqlQuery := `SELECT ` + selectColumns + ` FROM lessons WHERE title ILIKE '%' || $1 || '%' ORDER BY title`
	rows, err := r.db.Query(sqlQuery, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Lesson
	for rows.Next() {
		l, err := scanLesson(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, l)
	}
	return result, nil
}

// --- Admin Course Management (additive) ---

// Update applies only the provided (non-nil) fields.
func (r *Repository) Update(id int, req UpdateLessonRequest) error {
	res, err := r.db.Exec(`
		UPDATE lessons SET
			title = COALESCE($1, title),
			description = COALESCE($2, description),
			video_url = COALESCE($3, video_url),
			video_source = COALESCE($4, video_source),
			pdf_url = COALESCE($5, pdf_url),
			pdf_title = COALESCE($6, pdf_title),
			pdf_description = COALESCE($7, pdf_description),
			thumbnail_url = COALESCE($8, thumbnail_url),
			duration = COALESCE($9, duration)
		WHERE id = $10`,
		req.Title, req.Description, req.VideoURL, req.VideoSource, req.PDFURL, req.PDFTitle, req.PDFDescription, req.ThumbnailURL, req.Duration, id,
	)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrLessonNotFound
	}
	return nil
}

// Delete removes the lesson - lesson_progress/notes/etc cascade via
// existing FK constraints, unchanged from before.
func (r *Repository) Delete(id int) error {
	res, err := r.db.Exec(`DELETE FROM lessons WHERE id = $1`, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrLessonNotFound
	}
	return nil
}

// Reorder updates order_number for a batch of lessons in one transaction -
// powers drag-and-drop reordering.
func (r *Repository) Reorder(items []ReorderItem) error {
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, item := range items {
		if _, err := tx.Exec(`UPDATE lessons SET order_number = $1 WHERE id = $2`, item.OrderNumber, item.ID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (r *Repository) SetVideoURL(id int, url string) error {
	// Direct file uploads always set video_source back to "upload" -
	// this is what distinguishes an uploaded file from a pasted
	// YouTube URL (set via Update) when the player decides how to
	// render the lesson's video.
	_, err := r.db.Exec(`UPDATE lessons SET video_url = $1, video_source = 'upload' WHERE id = $2`, url, id)
	return err
}

func (r *Repository) SetPDFURL(id int, url string) error {
	_, err := r.db.Exec(`UPDATE lessons SET pdf_url = $1 WHERE id = $2`, url, id)
	return err
}

func (r *Repository) SetAssignmentURL(id int, url string) error {
	_, err := r.db.Exec(`UPDATE lessons SET assignment_url = $1 WHERE id = $2`, url, id)
	return err
}

// --- Lesson Resource Management (additive) ---

// SetStatus - used by Publish/Unpublish, same pattern as subjects.SetStatus.
func (r *Repository) SetStatus(id int, status string) error {
	res, err := r.db.Exec(`UPDATE lessons SET status = $1 WHERE id = $2`, status, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrLessonNotFound
	}
	return nil
}