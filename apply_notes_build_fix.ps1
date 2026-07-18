$Root = "C:\Users\ABC\Desktop\ai_tutor_app\backend"

New-Item -ItemType Directory -Force -Path "$Root\internal\notes" | Out-Null

# --- internal/notes/model.go ---
$content = @'
// Package notes implements PDF study notes attached to a lesson.
package notes

import (
	"errors"
	"time"
)

// Note mirrors the "notes" table row.
type Note struct {
	ID        int       `json:"id"`
	LessonID  int       `json:"lesson_id"`
	Title     string    `json:"title"`
	PDFURL    string    `json:"pdf_url"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateNoteRequest is the expected JSON body for POST /api/notes.
type CreateNoteRequest struct {
	LessonID int    `json:"lesson_id" binding:"required"`
	Title    string `json:"title" binding:"required"`
	PDFURL   string `json:"pdf_url" binding:"required"`
}

// --- Lesson Resource Management (additive) ---

// ErrNoteNotFound is returned by Update/Delete when the note id doesn't exist.
var ErrNoteNotFound = errors.New("note not found")

// UpdateNoteRequest - pointer fields mean "only update if present",
// same pattern as lessons.UpdateLessonRequest.
type UpdateNoteRequest struct {
	Title  *string `json:"title"`
	PDFURL *string `json:"pdf_url"`
}
'@
[System.IO.File]::WriteAllText("$Root\internal\notes\model.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: internal\notes\model.go"

# --- internal/notes/repository.go ---
$content = @'
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
'@
[System.IO.File]::WriteAllText("$Root\internal\notes\repository.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: internal\notes\repository.go"

# --- internal/notes/service.go ---
$content = @'
package notes

import "errors"

// Service contains the business logic for notes.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a notes Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ListByLesson returns every note attached to a lesson.
func (s *Service) ListByLesson(lessonID int) ([]Note, error) {
	return s.repo.FindByLessonID(lessonID)
}

// Create validates and inserts a new note.
func (s *Service) Create(req CreateNoteRequest) (int, error) {
	if req.Title == "" || req.PDFURL == "" {
		return 0, errors.New("title and pdf_url are required")
	}
	if req.LessonID <= 0 {
		return 0, errors.New("a valid lesson_id is required")
	}
	return s.repo.Create(req.LessonID, req.Title, req.PDFURL)
}

// --- Lesson Resource Management (additive) ---

// SyncForLesson keeps a single note in step with a lesson's pdf_url -
// used by the lessons package so uploading/replacing/removing a
// lesson's PDF (in the admin/teacher Lesson Resource Management
// dialog) also updates what students see via the existing notes list,
// without either package needing to know about the other's internals.
// An empty pdfURL removes the note; a non-empty one creates or updates it.
func (s *Service) SyncForLesson(lessonID int, title, pdfURL string) error {
	existing, err := s.repo.FindFirstByLessonID(lessonID)
	if err != nil {
		return err
	}
	if pdfURL == "" {
		if existing != nil {
			return s.repo.Delete(existing.ID)
		}
		return nil
	}
	if existing != nil {
		return s.repo.Update(existing.ID, title, pdfURL)
	}
	_, err = s.repo.Create(lessonID, title, pdfURL)
	return err
}

// Update applies only the provided (non-nil) fields to a note - used
// by PUT /api/notes/:id ("Replace PDF" / edit title).
func (s *Service) Update(id int, req UpdateNoteRequest) error {
	existing, err := s.repo.FindByID(id)
	if err != nil {
		return err
	}
	title := existing.Title
	if req.Title != nil {
		title = *req.Title
	}
	pdfURL := existing.PDFURL
	if req.PDFURL != nil {
		pdfURL = *req.PDFURL
	}
	return s.repo.Update(id, title, pdfURL)
}

// Delete removes a note - used by DELETE /api/notes/:id ("Remove PDF").
func (s *Service) Delete(id int) error {
	return s.repo.Delete(id)
}
'@
[System.IO.File]::WriteAllText("$Root\internal\notes\service.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: internal\notes\service.go"

# --- internal/notes/routes.go ---
$content = @'
package notes

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches /api/notes AND /api/lessons/:id/notes.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.POST("/notes", authMiddleware, handler.Create)
	router.GET("/lessons/:id/notes", authMiddleware, handler.ListByLesson)
	// Lesson Resource Management (additive)
	router.PUT("/notes/:id", authMiddleware, handler.Update)
	router.DELETE("/notes/:id", authMiddleware, handler.Delete)
}
'@
[System.IO.File]::WriteAllText("$Root\internal\notes\routes.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: internal\notes\routes.go"

Write-Host ""
Write-Host "All files written successfully." -ForegroundColor Green