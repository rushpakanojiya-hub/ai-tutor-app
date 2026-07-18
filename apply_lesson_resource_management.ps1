$Root = "C:\Users\ABC\Desktop\ai_tutor_app"

# --- Create directories if they do not exist ---
New-Item -ItemType Directory -Force -Path "$Root\backend\internal\lessons" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\backend\internal\subjects" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\backend\migrations" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\core\constants" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\models" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\screens\courses" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\screens\lessons" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\screens\profile" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\services" | Out-Null

# --- backend/internal/lessons/model.go ---
$content = @'
// Package lessons implements the third level of the hierarchy:
// each subject contains an ordered list of lessons with video + PDF content.
package lessons

import "time"

// Lesson mirrors the "lessons" table row.
type Lesson struct {
	ID              int       `json:"id"`
	SubjectID       int       `json:"subject_id"`
	Title           string    `json:"title"`
	Description     string    `json:"description"`
	VideoURL        string    `json:"video_url"`
	VideoSource     string    `json:"video_source"` // "upload" or "youtube"
	PDFURL          string    `json:"pdf_url"`
	PDFTitle        string    `json:"pdf_title"`
	PDFDescription  string    `json:"pdf_description"`
	AssignmentURL   string    `json:"assignment_url"`
	ThumbnailURL    string    `json:"thumbnail_url"`
	Duration        int       `json:"duration"` // minutes
	OrderNumber     int       `json:"order_number"`
	Status          string    `json:"status"` // "draft" or "published"
	CreatedAt       time.Time `json:"created_at"`
}

// --- Lesson Resource Management (additive) ---

const (
	StatusDraft     = "draft"
	StatusPublished = "published"
)

// CreateLessonRequest is the expected JSON body for POST /api/lessons.
type CreateLessonRequest struct {
	SubjectID    int    `json:"subject_id" binding:"required"`
	Title        string `json:"title" binding:"required"`
	Description  string `json:"description"`
	VideoURL     string `json:"video_url"`
	PDFURL       string `json:"pdf_url"`
	ThumbnailURL string `json:"thumbnail_url"`
	Duration     int    `json:"duration"`
	OrderNumber  int    `json:"order_number"`
}

// --- Admin Course Management (additive) ---

// UpdateLessonRequest - pointer fields mean "only update if present".
type UpdateLessonRequest struct {
	Title          *string `json:"title"`
	Description    *string `json:"description"`
	VideoURL       *string `json:"video_url"`
	VideoSource    *string `json:"video_source"`
	PDFURL         *string `json:"pdf_url"`
	PDFTitle       *string `json:"pdf_title"`
	PDFDescription *string `json:"pdf_description"`
	ThumbnailURL   *string `json:"thumbnail_url"`
	Duration       *int    `json:"duration"`
}

// ReorderItem pairs a lesson ID with its new order_number.
type ReorderItem struct {
	ID          int `json:"id" binding:"required"`
	OrderNumber int `json:"order_number"`
}

// ReorderLessonsRequest is the body for POST /api/subjects/:id/lessons/reorder.
type ReorderLessonsRequest struct {
	Items []ReorderItem `json:"items" binding:"required"`
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\lessons\model.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\lessons\model.go"

# --- backend/internal/lessons/handler.go ---
$content = @'
package lessons

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the lessons Service.
type Handler struct {
	service *Service
}

// NewHandler builds a lessons Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// ListBySubject handles GET /api/subjects/:id/lessons.
func (h *Handler) ListBySubject(c *gin.Context) {
	subjectID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid subject id")
		return
	}

	list, err := h.service.ListBySubject(subjectID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load lessons")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lessons fetched", list)
}

// GetByID handles GET /api/lessons/:id.
func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}

	lesson, err := h.service.GetByID(id)
	if err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load lesson")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson fetched", lesson)
}

// Create handles POST /api/lessons (admin-only).
//
// QA fix: previously had no role check - any authenticated user could
// create a lesson.
func (h *Handler) Create(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	var req CreateLessonRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "subject_id and title are required")
		return
	}

	id, err := h.service.Create(req)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Lesson created", gin.H{"id": id})
}

// --- Admin Course Management (additive) ---

// --- Lesson Resource Management (additive) ---
//
// Teachers manage lesson resources (create/edit/delete/upload/publish)
// same as admins; only admins keep exclusive rights elsewhere (course/
// category management). Student-facing GetByID/ListBySubject are
// unaffected - they stay open to any authenticated role, unchanged.
func requireAdminOrTeacher(c *gin.Context) bool {
	role := c.GetString("role")
	if role != "admin" && role != "teacher" {
		utils.RespondError(c, http.StatusForbidden, "Only admins or teachers can manage lessons")
		return false
	}
	return true
}

// Update handles PUT /api/lessons/:id (admin-only).
func (h *Handler) Update(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	var req UpdateLessonRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	if err := h.service.Update(id, req); err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson updated", nil)
}

// Delete handles DELETE /api/lessons/:id (admin-only).
func (h *Handler) Delete(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	if err := h.service.Delete(id); err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to delete lesson")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson deleted", nil)
}

// Reorder handles POST /api/subjects/:id/lessons/reorder (admin-only) -
// drag-and-drop reordering.
func (h *Handler) Reorder(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	var req ReorderLessonsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "items array is required")
		return
	}
	if err := h.service.Reorder(req.Items); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to reorder lessons")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lessons reordered", nil)
}

const maxUploadMultipartMemory = 25 << 20 // 25MB, matches MaxUploadSizeBytes

// Security audit fix (High: "File Upload Security"): the previous
// version accepted whatever c.FormFile("file") returned with no size
// check and no extension/type check at all server-side - only the
// Flutter client's FilePicker restricted extensions, which is trivial
// to bypass with a direct API call (e.g. curl). readUploadedFile now
// takes the caller's allowed extensions and enforces both the 25MB cap
// and the extension whitelist before ever reading the file into memory
// or forwarding it to Cloudinary.
func readUploadedFile(c *gin.Context, allowedExtensions []string) ([]byte, string, error) {
	file, err := c.FormFile("file")
	if err != nil {
		return nil, "", err
	}
	if file.Size > maxUploadMultipartMemory {
		return nil, "", fmt.Errorf("file exceeds the 25MB limit")
	}
	ext := strings.ToLower(filepath.Ext(file.Filename))
	allowed := false
	for _, a := range allowedExtensions {
		if ext == a {
			allowed = true
			break
		}
	}
	if !allowed {
		return nil, "", fmt.Errorf("file type %s is not allowed", ext)
	}

	f, err := file.Open()
	if err != nil {
		return nil, "", err
	}
	defer f.Close()
	bytes, err := io.ReadAll(f)
	if err != nil {
		return nil, "", err
	}
	return bytes, file.Filename, nil
}

// UploadVideo handles POST /api/lessons/:id/upload-video (admin-only, multipart).
func (h *Handler) UploadVideo(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	fileBytes, filename, err := readUploadedFile(c, []string{".mp4", ".mov"})
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A valid video file (mp4/mov, up to 25MB) is required")
		return
	}
	url, err := h.service.UploadVideo(id, fileBytes, filename)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to upload video")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Video uploaded", gin.H{"video_url": url})
}

// UploadPDF handles POST /api/lessons/:id/upload-pdf (admin-only, multipart).
func (h *Handler) UploadPDF(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	fileBytes, filename, err := readUploadedFile(c, []string{".pdf"})
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A valid PDF file (up to 25MB) is required")
		return
	}
	url, err := h.service.UploadPDF(id, fileBytes, filename)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to upload PDF")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "PDF uploaded", gin.H{"pdf_url": url})
}

// UploadAssignment handles POST /api/lessons/:id/upload-assignment (admin-only, multipart).
func (h *Handler) UploadAssignment(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	fileBytes, filename, err := readUploadedFile(c, []string{".pdf", ".doc", ".docx"})
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A valid assignment file (pdf/doc/docx, up to 25MB) is required")
		return
	}
	url, err := h.service.UploadAssignment(id, fileBytes, filename)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to upload assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment uploaded", gin.H{"assignment_url": url})
}

// --- Lesson Resource Management (additive) ---

// Publish handles POST /api/lessons/:id/publish (admin/teacher).
func (h *Handler) Publish(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	if err := h.service.Publish(id); err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		if errors.Is(err, ErrNoResourcesYet) {
			utils.RespondError(c, http.StatusConflict, "At least one video or PDF is required before publishing")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to publish lesson")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson published", nil)
}

// Unpublish handles POST /api/lessons/:id/unpublish (admin/teacher).
func (h *Handler) Unpublish(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	if err := h.service.Unpublish(id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to unpublish lesson")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson unpublished", nil)
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\lessons\handler.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\lessons\handler.go"

# --- backend/internal/lessons/repository.go ---
$content = @'
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
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\lessons\repository.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\lessons\repository.go"

# --- backend/internal/lessons/service.go ---
$content = @'
package lessons

import (
	"errors"
	"log"

	"ai-tutor-backend/internal/cloudinary"
)

// MaxUploadSizeBytes matches the ceiling already used for class resource
// uploads elsewhere in the app.
const MaxUploadSizeBytes = 25 * 1024 * 1024

// Service contains the business logic for lessons.
type Service struct {
	repo            *Repository
	cloudinaryClient *cloudinary.Client
}

// NewService wires a Repository and the shared Cloudinary client into a
// lessons Service.
func NewService(repo *Repository, cloudinaryClient *cloudinary.Client) *Service {
	return &Service{repo: repo, cloudinaryClient: cloudinaryClient}
}

// ListBySubject returns every lesson for a subject.
func (s *Service) ListBySubject(subjectID int) ([]Lesson, error) {
	return s.repo.FindBySubjectID(subjectID)
}

// GetByID returns a single lesson by ID.
func (s *Service) GetByID(id int) (*Lesson, error) {
	return s.repo.FindByID(id)
}

// Create validates and inserts a new lesson.
func (s *Service) Create(req CreateLessonRequest) (int, error) {
	if req.SubjectID <= 0 {
		return 0, errors.New("a valid subject_id is required")
	}
	if req.Title == "" {
		return 0, errors.New("lesson title is required")
	}
	return s.repo.Create(req)
}

// --- Admin Course Management (additive) ---

func (s *Service) Update(id int, req UpdateLessonRequest) error {
	if req.Title != nil && *req.Title == "" {
		return errors.New("lesson title is required")
	}
	return s.repo.Update(id, req)
}

func (s *Service) Delete(id int) error {
	return s.repo.Delete(id)
}

func (s *Service) Reorder(items []ReorderItem) error {
	return s.repo.Reorder(items)
}

// --- Lesson Resource Management (additive) ---

// ErrNoResourcesYet - a lesson can only be published once it has at
// least one video or PDF attached (draft is allowed without any).
var ErrNoResourcesYet = errors.New("at least one video or PDF is required before publishing")

// Publish enforces "at least one video or PDF required before publishing" -
// same shape as subjects.Service.Publish's lesson-count check.
func (s *Service) Publish(id int) error {
	lesson, err := s.repo.FindByID(id)
	if err != nil {
		return err
	}
	if lesson.VideoURL == "" && lesson.PDFURL == "" {
		return ErrNoResourcesYet
	}
	return s.repo.SetStatus(id, StatusPublished)
}

func (s *Service) Unpublish(id int) error {
	return s.repo.SetStatus(id, StatusDraft)
}

// UploadVideo, UploadPDF, UploadAssignment - same Cloudinary pattern
// already used for live-class resource uploads (internal/resource).
func (s *Service) UploadVideo(lessonID int, fileBytes []byte, filename string) (string, error) {
	result, err := s.cloudinaryClient.Upload(fileBytes, filename, "video")
	if err != nil {
		log.Printf("[lessons] Cloudinary video upload failed for %q: %v", filename, err)
		return "", err
	}
	if err := s.repo.SetVideoURL(lessonID, result.SecureURL); err != nil {
		return "", err
	}
	return result.SecureURL, nil
}

func (s *Service) UploadPDF(lessonID int, fileBytes []byte, filename string) (string, error) {
	result, err := s.cloudinaryClient.Upload(fileBytes, filename, "raw")
	if err != nil {
		log.Printf("[lessons] Cloudinary PDF upload failed for %q: %v", filename, err)
		return "", err
	}
	if err := s.repo.SetPDFURL(lessonID, result.SecureURL); err != nil {
		return "", err
	}
	return result.SecureURL, nil
}

func (s *Service) UploadAssignment(lessonID int, fileBytes []byte, filename string) (string, error) {
	result, err := s.cloudinaryClient.Upload(fileBytes, filename, "raw")
	if err != nil {
		log.Printf("[lessons] Cloudinary assignment upload failed for %q: %v", filename, err)
		return "", err
	}
	if err := s.repo.SetAssignmentURL(lessonID, result.SecureURL); err != nil {
		return "", err
	}
	return result.SecureURL, nil
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\lessons\service.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\lessons\service.go"

# --- backend/internal/lessons/routes.go ---
$content = @'
package lessons

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches /api/lessons/* AND /api/subjects/:id/lessons
// (the latter lives here for the same reason subjects/:id/subjects lives
// in the subjects package - it's fundamentally a lessons list).
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	lessonsGroup := router.Group("/lessons")
	lessonsGroup.Use(authMiddleware)
	{
		lessonsGroup.GET("/:id", handler.GetByID)
		lessonsGroup.POST("", handler.Create)
		// Admin Course Management (additive) - all admin-gated inside
		// the handler itself.
		lessonsGroup.PUT("/:id", handler.Update)
		lessonsGroup.DELETE("/:id", handler.Delete)
		lessonsGroup.POST("/:id/upload-video", handler.UploadVideo)
		lessonsGroup.POST("/:id/upload-pdf", handler.UploadPDF)
		lessonsGroup.POST("/:id/upload-assignment", handler.UploadAssignment)
		// Lesson Resource Management (additive)
		lessonsGroup.POST("/:id/publish", handler.Publish)
		lessonsGroup.POST("/:id/unpublish", handler.Unpublish)
	}
	router.GET("/subjects/:id/lessons", authMiddleware, handler.ListBySubject)
	router.POST("/subjects/:id/lessons/reorder", authMiddleware, handler.Reorder)
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\lessons\routes.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\lessons\routes.go"

# --- backend/internal/subjects/handler.go ---
$content = @'
package subjects

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the subjects Service.
type Handler struct {
	service *Service
}

// NewHandler builds a subjects Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// List handles GET /api/subjects.
func (h *Handler) List(c *gin.Context) {
	userID := c.GetInt("user_id")

	list, err := h.service.List(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load subjects")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Subjects fetched", list)
}

// ListByCategory handles GET /api/categories/:id/subjects.
func (h *Handler) ListByCategory(c *gin.Context) {
	categoryID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid category id")
		return
	}

	userID := c.GetInt("user_id")

	list, err := h.service.ListByCategory(userID, categoryID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load subjects")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Subjects fetched", list)
}

// GetByID handles GET /api/subjects/:id.
func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid subject id")
		return
	}

	userID := c.GetInt("user_id")

	subject, err := h.service.GetByID(userID, id)
	if err != nil {
		if errors.Is(err, ErrSubjectNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Subject not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load subject")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Subject fetched", subject)
}

// Create handles POST /api/subjects (admin-only).
//
// QA fix: previously had no role check - any authenticated user could
// create a subject.
func (h *Handler) Create(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	var req CreateSubjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return
	}

	id, err := h.service.Create(req)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Subject created", gin.H{"id": id})
}

// --- Admin Course Management ---

func requireAdmin(c *gin.Context) bool {
	if c.GetString("role") != "admin" {
		utils.RespondError(c, http.StatusForbidden, "Only admins can manage courses")
		return false
	}
	return true
}

// --- Lesson Resource Management (additive) ---
//
// Teachers need to browse the course list read-only so they can drill
// into a course's lessons and manage video/PDF resources there (lessons
// handler already accepts admin or teacher). Course/category CRUD stays
// admin-only, unchanged - only this listing endpoint is opened up.
func requireAdminOrTeacherReadOnly(c *gin.Context) bool {
	role := c.GetString("role")
	if role != "admin" && role != "teacher" {
		utils.RespondError(c, http.StatusForbidden, "Only admins or teachers can view course management")
		return false
	}
	return true
}

// AdminList handles GET /api/admin/courses?search=&category_id=&status=.
func (h *Handler) AdminList(c *gin.Context) {
	if !requireAdminOrTeacherReadOnly(c) {
		return
	}
	search := c.Query("search")
	var categoryID *int
	if v, err := strconv.Atoi(c.Query("category_id")); err == nil {
		categoryID = &v
	}
	var status *string
	if v := c.Query("status"); v != "" {
		status = &v
	}

	list, err := h.service.AdminList(search, categoryID, status)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load courses")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Courses fetched", list)
}

// Update handles PUT /api/subjects/:id (admin-only).
func (h *Handler) Update(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid course id")
		return
	}
	var req UpdateCourseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	if err := h.service.Update(id, req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Course updated", nil)
}

// Delete handles DELETE /api/subjects/:id (admin-only).
func (h *Handler) Delete(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid course id")
		return
	}
	if err := h.service.Delete(id); err != nil {
		if errors.Is(err, ErrCourseNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Course not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to delete course")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Course deleted", nil)
}

// Publish handles POST /api/subjects/:id/publish (admin-only).
func (h *Handler) Publish(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid course id")
		return
	}
	if err := h.service.Publish(id); err != nil {
		if errors.Is(err, ErrNoLessonsYet) {
			utils.RespondError(c, http.StatusConflict, "At least one lesson is required before publishing")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to publish course")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Course published", nil)
}

// Unpublish handles POST /api/subjects/:id/unpublish (admin-only).
func (h *Handler) Unpublish(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid course id")
		return
	}
	if err := h.service.Unpublish(id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to unpublish course")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Course unpublished", nil)
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\subjects\handler.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\subjects\handler.go"

# --- backend/migrations/027_lesson_resource_management.sql ---
$content = @'
-- Lesson Resource Management: lessons need a publish/draft lifecycle
-- (same pattern as subjects.status from migration 025), a way to tell
-- an uploaded video apart from a pasted YouTube URL, and a title/
-- description for the PDF notes attached to a lesson.
-- Safe to run on existing DB. Does NOT touch auth, categories, subjects,
-- notes, search, progress-tracking, or ai_tutor tables.

BEGIN;

ALTER TABLE lessons
    ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'draft',
    ADD COLUMN IF NOT EXISTS video_source VARCHAR(20) NOT NULL DEFAULT 'upload',
    ADD COLUMN IF NOT EXISTS pdf_title TEXT,
    ADD COLUMN IF NOT EXISTS pdf_description TEXT;

CREATE INDEX IF NOT EXISTS idx_lessons_status ON lessons(status);

COMMIT;
'@
[System.IO.File]::WriteAllText("$Root\backend\migrations\027_lesson_resource_management.sql", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\migrations\027_lesson_resource_management.sql"

# --- frontend/lib/models/course_model.dart ---
$content = @'
class AdminCourseModel {
  final int id;
  final String name;
  final String description;
  final String thumbnail;
  final String difficulty;
  final String status; // draft | published
  final int categoryId;
  final String categoryName;
  final int totalLessons;
  final int enrolledCount;

  AdminCourseModel({
    required this.id,
    required this.name,
    required this.description,
    required this.thumbnail,
    required this.difficulty,
    required this.status,
    required this.categoryId,
    required this.categoryName,
    required this.totalLessons,
    required this.enrolledCount,
  });

  factory AdminCourseModel.fromJson(Map<String, dynamic> json) {
    return AdminCourseModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? 'Intermediate',
      status: json['status'] as String? ?? 'draft',
      categoryId: json['category_id'] as int? ?? 0,
      categoryName: json['category_name'] as String? ?? '',
      totalLessons: json['total_lessons'] as int? ?? 0,
      enrolledCount: json['enrolled_count'] as int? ?? 0,
    );
  }
}

class AdminLessonModel {
  final int id;
  final int subjectId;
  final String title;
  final String description;
  final String videoUrl;
  final String videoSource; // 'upload' | 'youtube'
  final String pdfUrl;
  final String pdfTitle;
  final String pdfDescription;
  final String assignmentUrl;
  final int duration;
  final int orderNumber;
  final String status; // 'draft' | 'published'

  AdminLessonModel({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.videoSource,
    required this.pdfUrl,
    required this.pdfTitle,
    required this.pdfDescription,
    required this.assignmentUrl,
    required this.duration,
    required this.orderNumber,
    required this.status,
  });

  factory AdminLessonModel.fromJson(Map<String, dynamic> json) {
    return AdminLessonModel(
      id: json['id'] as int? ?? 0,
      subjectId: json['subject_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      videoSource: json['video_source'] as String? ?? 'upload',
      pdfUrl: json['pdf_url'] as String? ?? '',
      pdfTitle: json['pdf_title'] as String? ?? '',
      pdfDescription: json['pdf_description'] as String? ?? '',
      assignmentUrl: json['assignment_url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      orderNumber: json['order_number'] as int? ?? 0,
      status: json['status'] as String? ?? 'draft',
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\models\course_model.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\models\course_model.dart"

# --- frontend/lib/models/lesson_model.dart ---
$content = @'
/// Plain data model for a single lesson (video + optional PDF content).
class LessonModel {
  final int id;
  final int subjectId;
  final String title;
  final String description;
  final String videoUrl;
  final String videoSource; // 'upload' | 'youtube' - decides how the player renders it
  final String pdfUrl;
  final String thumbnailUrl;
  final int duration; // minutes
  final int orderNumber;

  /// Not part of the API response - set locally by the UI once a lesson
  /// has been marked complete via the backend, so LessonsScreen can show a
  /// checkmark (see LessonProvider.loadLessons, which merges in real
  /// persisted completion from GET /api/progress/subjects/:id).
  bool isCompleted;

  LessonModel({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.videoSource,
    required this.pdfUrl,
    required this.thumbnailUrl,
    required this.duration,
    required this.orderNumber,
    this.isCompleted = false,
  });

  factory LessonModel.fromJson(Map<String, dynamic> json) {
    return LessonModel(
      id: json['id'] as int? ?? 0,
      subjectId: json['subject_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      videoSource: json['video_source'] as String? ?? 'upload',
      pdfUrl: json['pdf_url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      orderNumber: json['order_number'] as int? ?? 0,
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\models\lesson_model.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\models\lesson_model.dart"

# --- frontend/lib/services/course_service.dart ---
$content = @'
import 'dart:io';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../models/category_model.dart';
import '../models/course_model.dart';
import 'api_service.dart';

/// Admin-only Course Management: covers Categories, Courses (subjects),
/// and Lessons - create/edit/delete/publish/reorder/upload. Every call
/// here hits an admin-gated backend endpoint; the backend itself
/// rejects non-admin callers with 403, this service does not duplicate
/// that check client-side.
class CourseService {
  final ApiService _api = ApiService();

  // --- Courses (subjects) ---

  Future<List<AdminCourseModel>> listCourses({String search = '', int? categoryId, String? status}) async {
    final response = await _api.get(ApiConstants.adminCourses(search: search, categoryId: categoryId, status: status));
    final list = response['data'] as List<dynamic>? ?? [];
    return list.map((json) => AdminCourseModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<int> createCourse({required int categoryId, required String name, String description = '', String thumbnail = ''}) async {
    final response = await _api.post(ApiConstants.subjects, {
      'category_id': categoryId,
      'name': name,
      'description': description,
      'thumbnail': thumbnail,
    });
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['id'] as int? ?? 0;
  }

  Future<void> updateCourse(int id, {int? categoryId, String? name, String? description, String? thumbnail, String? difficulty}) async {
    final body = <String, dynamic>{};
    if (categoryId != null) body['category_id'] = categoryId;
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (thumbnail != null) body['thumbnail'] = thumbnail;
    if (difficulty != null) body['difficulty'] = difficulty;
    await _api.put(ApiConstants.course(id), body);
  }

  Future<void> deleteCourse(int id) async {
    await _api.delete(ApiConstants.course(id));
  }

  Future<void> publishCourse(int id) async {
    await _api.post(ApiConstants.coursePublish(id), {});
  }

  Future<void> unpublishCourse(int id) async {
    await _api.post(ApiConstants.courseUnpublish(id), {});
  }

  // --- Categories ---

  Future<List<CategoryModel>> listCategories() async {
    final response = await _api.get(ApiConstants.categories);
    final list = response['data'] as List<dynamic>? ?? [];
    return list.map((json) => CategoryModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<int> createCategory(String name, {String icon = ''}) async {
    final response = await _api.post(ApiConstants.categories, {'name': name, 'icon': icon});
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['id'] as int? ?? 0;
  }

  Future<void> updateCategory(int id, {String? name, String? icon}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (icon != null) body['icon'] = icon;
    await _api.put(ApiConstants.categoryUpdate(id), body);
  }

  // --- Lessons ---

  Future<List<AdminLessonModel>> listLessons(int subjectId) async {
    final response = await _api.get(ApiConstants.subjectLessons(subjectId));
    final list = response['data'] as List<dynamic>? ?? [];
    return list.map((json) => AdminLessonModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<int> createLesson({required int subjectId, required String title, String description = '', int duration = 0, int orderNumber = 0}) async {
    final response = await _api.post(ApiConstants.lessonsCreate, {
      'subject_id': subjectId,
      'title': title,
      'description': description,
      'duration': duration,
      'order_number': orderNumber,
    });
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['id'] as int? ?? 0;
  }

  Future<void> updateLesson(
    int id, {
    String? title,
    String? description,
    int? duration,
    String? videoUrl,
    String? videoSource,
    String? pdfUrl,
    String? pdfTitle,
    String? pdfDescription,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (duration != null) body['duration'] = duration;
    if (videoUrl != null) body['video_url'] = videoUrl;
    if (videoSource != null) body['video_source'] = videoSource;
    if (pdfUrl != null) body['pdf_url'] = pdfUrl;
    if (pdfTitle != null) body['pdf_title'] = pdfTitle;
    if (pdfDescription != null) body['pdf_description'] = pdfDescription;
    await _api.put(ApiConstants.lessonById(id), body);
  }

  // --- Lesson Resource Management (additive) ---

  Future<void> publishLesson(int id) async {
    await _api.post(ApiConstants.lessonPublish(id), {});
  }

  Future<void> unpublishLesson(int id) async {
    await _api.post(ApiConstants.lessonUnpublish(id), {});
  }

  Future<void> deleteLesson(int id) async {
    await _api.delete(ApiConstants.lessonById(id));
  }

  Future<void> reorderLessons(int subjectId, List<Map<String, int>> items) async {
    await _api.post(ApiConstants.lessonsReorder(subjectId), {'items': items});
  }

  Future<String> uploadLessonVideo(int lessonId, File file) async {
    final formData = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split(Platform.pathSeparator).last)});
    final response = await _api.postMultipart(ApiConstants.lessonUploadVideo(lessonId), formData);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['video_url'] as String? ?? '';
  }

  Future<String> uploadLessonPdf(int lessonId, File file) async {
    final formData = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split(Platform.pathSeparator).last)});
    final response = await _api.postMultipart(ApiConstants.lessonUploadPdf(lessonId), formData);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['pdf_url'] as String? ?? '';
  }

  Future<String> uploadLessonAssignment(int lessonId, File file) async {
    final formData = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split(Platform.pathSeparator).last)});
    final response = await _api.postMultipart(ApiConstants.lessonUploadAssignment(lessonId), formData);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return data['assignment_url'] as String? ?? '';
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\services\course_service.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\services\course_service.dart"

# --- frontend/lib/core/constants/api_constants.dart ---
$content = @'
/// Centralized API configuration so base URLs and endpoint paths
/// only ever need to change in one place.
class ApiConstants {
  ApiConstants._();

  /// Android emulator maps 10.0.2.2 to the host machine's localhost.
  /// - Physical device / real backend: replace with your machine's LAN IP
  ///   or your deployed Render URL, e.g. https://your-app.onrender.com
  /// - iOS simulator: use http://localhost:8080
  static const String baseUrl = 'http://192.168.1.13:8080/api';

  // --- Day 1: Auth ---
  static const String register = '/auth/register';
  static const String badgesMine = '/badges/mine';
  static String badgesForStudent(int studentId) => '/badges/student/$studentId';
  static const String xpMine = '/xp/mine';
  static String leaderboard({String period = 'overall', String? classFilter, String? section}) {
    var path = '/leaderboard?period=$period';
    if (classFilter != null && classFilter.isNotEmpty) path += '&class=$classFilter';
    if (section != null && section.isNotEmpty) path += '&section=$section';
    return path;
  }
  static String assignClassSection(int studentId) => '/admin/students/$studentId/class-section';
  static const String adminStudents = '/admin/students';
  static const String certificatesMine = '/certificates/mine';
  static const String certificatesTeacher = '/certificates/teacher';
  static const String certificatesAll = '/certificates/all';
  static String certificate(int id) => '/certificates/$id';
  static String adminCourses({String? search, int? categoryId, String? status}) {
    var path = '/admin/courses?';
    final params = <String>[];
    if (search != null && search.isNotEmpty) params.add('search=${Uri.encodeQueryComponent(search)}');
    if (categoryId != null) params.add('category_id=$categoryId');
    if (status != null && status.isNotEmpty) params.add('status=$status');
    return path + params.join('&');
  }
  static String course(int id) => '/subjects/$id';
  static String coursePublish(int id) => '/subjects/$id/publish';
  static String courseUnpublish(int id) => '/subjects/$id/unpublish';
  static String categoryUpdate(int id) => '/categories/$id';
  static const String lessonsCreate = '/lessons';
  static String lessonsReorder(int subjectId) => '/subjects/$subjectId/lessons/reorder';
  static String lessonUploadVideo(int id) => '/lessons/$id/upload-video';
  static String lessonUploadPdf(int id) => '/lessons/$id/upload-pdf';
  static String lessonUploadAssignment(int id) => '/lessons/$id/upload-assignment';
  // Lesson Resource Management (additive)
  static String lessonPublish(int id) => '/lessons/$id/publish';
  static String lessonUnpublish(int id) => '/lessons/$id/unpublish';
  static const String teacherApply = '/auth/teacher/apply';
  static const String login = '/auth/login';
  static const String profile = '/auth/profile';
  static const String updateProfile = '/users/profile';
  static const String changePassword = '/users/change-password';

  // --- Day 2: Course & Learning Management ---
  static const String categories = '/categories';
  static String categorySubjects(int categoryId) => '/categories/$categoryId/subjects';
  static const String subjects = '/subjects';
  static String subjectById(int subjectId) => '/subjects/$subjectId';
  static String subjectLessons(int subjectId) => '/subjects/$subjectId/lessons';
  static String lessonById(int lessonId) => '/lessons/$lessonId';
  static String lessonNotes(int lessonId) => '/lessons/$lessonId/notes';
  static String lessonAiContent(int lessonId) => '/lessons/$lessonId/ai-content';
  static const String search = '/search';

  // --- Progress tracking ---
  static String markLessonComplete(int lessonId) => '/progress/lessons/$lessonId/complete';
  static String subjectProgress(int subjectId) => '/progress/subjects/$subjectId';

  // --- AI Tutor ---
  static const String aiChat = '/ai/chat';
  static const String aiSessions = '/ai/sessions';
  static String aiSession(int id) => '/ai/sessions/$id';
  static const String aiRecommendations = '/ai/recommendations';

  // --- YouTube video integration ---
  static String lessonVideos(int lessonId) => '/lessons/$lessonId/videos';
  static String lessonVideoProgress(int lessonId) => '/lessons/$lessonId/videos/progress';
  static const String videoSearch = '/videos/search';

  // --- Quiz & Assessment ---
  static String submitLessonQuizAttempt(int lessonId) => '/quiz/lessons/$lessonId/attempt';
  static const String submitFreeformQuizAttempt = '/quiz/freeform/attempt';
  static const String quizAttempts = '/quiz/attempts';
  static String quizAttempt(int id) => '/quiz/attempts/$id';
  static const String quizAnalytics = '/quiz/analytics';
  static const String quizGenerate = '/quiz/generate';

  // --- Learning Streak ---
  static const String streak = '/streak';

  // --- Admin Panel ---
  static const String adminDashboard = '/admin/dashboard';
  static const String adminPendingTeachers = '/auth/admin/teachers/pending';
  static String adminApproveTeacher(int id) => '/auth/admin/teachers/$id/approve';
  static String adminRejectTeacher(int id) => '/auth/admin/teachers/$id/reject';

  // --- Assignments ---
  static const String assignments = '/assignments';
  static String assignment(int id) => '/assignments/$id';
  static String assignmentPublish(int id) => '/assignments/$id/publish';
  static String assignmentUnpublish(int id) => '/assignments/$id/unpublish';
  static String assignmentClose(int id) => '/assignments/$id/close';
  static String assignmentArchive(int id) => '/assignments/$id/archive';
  static const String assignmentGenerateAI = '/assignments/generate-ai';
  static const String myAssignments = '/assignments/mine';
  static const String teacherAssignmentAnalytics = '/assignments/analytics';
  static String assignmentSubmissions(int id) => '/assignments/$id/submissions';
  static String reviewSubmission(int id) => '/assignments/submissions/$id/review';
  static String assignmentDraft(int id) => '/assignments/$id/draft';
  static String assignmentSubmit(int id) => '/assignments/$id/submit';
  static String mySubmission(int id) => '/assignments/$id/my-submission';
  static String retryEvaluation(int submissionId) => '/assignments/submissions/$submissionId/retry-evaluation';
  static const String assignmentsForStudent = '/assignments/for-student';
  static String subjectAssignments(int subjectId) => '/subjects/$subjectId/assignments';
  static const String adminAssignments = '/admin/assignments';
  static const String adminAssignmentAnalytics = '/admin/assignments/analytics';

  // --- Live Classes (Phase 1: scheduling only, no video) ---
  static const String liveClasses = '/live-classes';
  static String liveClass(int id) => '/live-classes/$id';
  static String liveClassCancel(int id) => '/live-classes/$id/cancel';
  static String liveClassComplete(int id) => '/live-classes/$id/complete';
  static const String myLiveClasses = '/live-classes/mine';
  static const String liveClassesForStudent = '/live-classes/for-student';
  static const String adminLiveClasses = '/admin/live-classes';
  static String adminLiveClassCancel(int id) => '/admin/live-classes/$id/cancel';
  static String liveClassCheckIn(int id) => '/live-classes/$id/check-in';
  static String liveClassMyAttendance(int id) => '/live-classes/$id/my-attendance';
  static String liveClassAttendance(int id) => '/live-classes/$id/attendance';
  static const String liveClassAttendanceSummary = '/live-classes/attendance-summary';
  static String liveClassStart(int id) => '/live-classes/$id/start';
  static String liveClassJoin(int id) => '/live-classes/$id/join';
  static String liveClassEnd(int id) => '/live-classes/$id/end';
  static String liveClassMeetingStatus(int id) => '/live-classes/$id/meeting-status';
  static String liveClassResources(int id) => '/live-classes/$id/resources';
  static String liveClassResourceDelete(int classId, int resourceId) => '/live-classes/$classId/resources/$resourceId';
  static String liveClassMute(int id, String identity) => '/live-classes/$id/mute/$identity';
  static String liveClassRemove(int id, String identity) => '/live-classes/$id/remove/$identity';
  static String liveClassMuteAll(int id) => '/live-classes/$id/mute-all';
  static String liveClassLock(int id) => '/live-classes/$id/lock';
  static String liveClassUnlock(int id) => '/live-classes/$id/unlock';

  // --- Notifications ---
  static const String notifications = '/notifications';
  static const String notificationUnreadCount = '/notifications/unread-count';
  static String notificationRead(int id) => '/notifications/$id/read';
  static const String notificationReadAll = '/notifications/read-all';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// Resolves a possibly-relative media path (e.g. "/static/notes/x.pdf",
  /// stored in the DB so it works on any host) into a full URL using the
  /// same host as [baseUrl]. Already-absolute URLs (http/https) pass through
  /// unchanged, so externally hosted media still works too.
  static String resolveMediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final origin = baseUrl.replaceAll('/api', '');
    return '$origin$path';
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\core\constants\api_constants.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\core\constants\api_constants.dart"

# --- frontend/lib/screens/courses/lesson_management_screen.dart ---
$content = @'
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/course_model.dart';
import '../../services/course_service.dart';

/// Admin-only: manage a course's lessons - create, edit, delete, drag-
/// and-drop reorder, and upload video/PDF/assignment files (via
/// Cloudinary, same pattern as Class Resources uploads elsewhere).
class LessonManagementScreen extends StatefulWidget {
  final int courseId;
  final String courseName;
  const LessonManagementScreen({super.key, required this.courseId, required this.courseName});

  @override
  State<LessonManagementScreen> createState() => _LessonManagementScreenState();
}

class _LessonManagementScreenState extends State<LessonManagementScreen> {
  final CourseService _service = CourseService();
  List<AdminLessonModel> _lessons = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _lessons = await _service.listLessons(widget.courseId);
    } catch (_) {
      // best-effort
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _lessons.removeAt(oldIndex);
      _lessons.insert(newIndex, item);
    });
    final items = [
      for (var i = 0; i < _lessons.length; i++) {'id': _lessons[i].id, 'order_number': i}
    ];
    try {
      await _service.reorderLessons(widget.courseId, items);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save new order.')));
      _load();
    }
  }

  Future<void> _showLessonDialog({AdminLessonModel? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _LessonEditorDialog(
        subjectId: widget.courseId,
        existing: existing,
        service: _service,
        nextOrderNumber: _lessons.length,
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _confirmDeleteLesson(AdminLessonModel lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Lesson?'),
        content: Text('Delete "${lesson.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteLesson(lesson.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete lesson.')));
    }
  }

  Future<void> _uploadFile(AdminLessonModel lesson, String kind) async {
    final extensions = kind == 'video' ? ['mp4', 'mov'] : ['pdf'];
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensions);
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploading ${kind}...'), duration: const Duration(seconds: 30)));

    try {
      if (kind == 'video') {
        await _service.uploadLessonVideo(lesson.id, file);
      } else if (kind == 'pdf') {
        await _service.uploadLessonPdf(lesson.id, file);
      } else {
        await _service.uploadLessonAssignment(lesson.id, file);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload complete.')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Lessons - ${widget.courseName}')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showLessonDialog(),
        backgroundColor: AppColors.purple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lessons.isEmpty
              ? const Center(child: Text('No lessons yet. Tap + to add one.'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _lessons.length,
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                    final lesson = _lessons[index];
                    return Card(
                      key: ValueKey(lesson.id),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        leading: CircleAvatar(backgroundColor: AppColors.purpleLight, child: Text('${index + 1}', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700))),
                        title: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Row(
                          children: [
                            Text(lesson.duration > 0 ? '${lesson.duration} min' : 'No duration set', style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: lesson.status == 'published' ? AppColors.green.withOpacity(0.15) : Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                lesson.status == 'published' ? 'Published' : 'Draft',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: lesson.status == 'published' ? AppColors.green : AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary)),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _actionChip(Icons.videocam_outlined, lesson.videoUrl.isNotEmpty ? 'Video ✓' : 'Upload Video', () => _uploadFile(lesson, 'video')),
                                    _actionChip(Icons.picture_as_pdf_outlined, lesson.pdfUrl.isNotEmpty ? 'PDF ✓' : 'Upload PDF', () => _uploadFile(lesson, 'pdf')),
                                    _actionChip(Icons.assignment_outlined, lesson.assignmentUrl.isNotEmpty ? 'Assignment ✓' : 'Upload Assignment', () => _uploadFile(lesson, 'assignment')),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _showLessonDialog(existing: lesson),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      label: const Text('Edit'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _confirmDeleteLesson(lesson),
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.purple),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}

// --- Lesson Resource Management (additive) ---
//
// Everything needed to manage a lesson's resources lives in this one
// dialog - title/description, video (upload OR YouTube URL, with
// preview/replace/remove), PDF notes (upload + title/description, with
// preview/replace/remove), and Save Draft / Publish / Unpublish. No
// separate Video/PDF pages are created, per spec.
class _LessonEditorDialog extends StatefulWidget {
  final int subjectId;
  final AdminLessonModel? existing;
  final CourseService service;
  final int nextOrderNumber;

  const _LessonEditorDialog({
    required this.subjectId,
    required this.existing,
    required this.service,
    required this.nextOrderNumber,
  });

  @override
  State<_LessonEditorDialog> createState() => _LessonEditorDialogState();
}

class _LessonEditorDialogState extends State<_LessonEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _durationController;
  late final TextEditingController _pdfTitleController;
  late final TextEditingController _pdfDescController;
  late final TextEditingController _youtubeController;

  int? _lessonId;
  String _videoUrl = '';
  String _videoSource = 'upload'; // 'upload' | 'youtube'
  String _pdfUrl = '';
  String _status = 'draft'; // 'draft' | 'published'

  bool _savingBasic = false;
  bool _uploadingVideo = false;
  bool _uploadingPdf = false;
  bool _publishing = false;

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _showVideoPreview = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _descController = TextEditingController(text: existing?.description ?? '');
    _durationController = TextEditingController(text: existing != null ? existing.duration.toString() : '');
    _pdfTitleController = TextEditingController(text: existing?.pdfTitle ?? '');
    _pdfDescController = TextEditingController(text: existing?.pdfDescription ?? '');
    _youtubeController = TextEditingController(text: existing?.videoSource == 'youtube' ? existing?.videoUrl ?? '' : '');

    _lessonId = existing?.id;
    _videoUrl = existing?.videoUrl ?? '';
    _videoSource = existing?.videoSource ?? 'upload';
    _pdfUrl = existing?.pdfUrl ?? '';
    _status = existing?.status ?? 'draft';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _durationController.dispose();
    _pdfTitleController.dispose();
    _pdfDescController.dispose();
    _youtubeController.dispose();
    _disposeVideoPreview();
    super.dispose();
  }

  void _disposeVideoPreview() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Creates the lesson (if it doesn't exist yet) or persists the basic
  /// text fields. Returns true on success.
  Future<bool> _saveBasicFields() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _toast('Lesson title is required.');
      return false;
    }
    setState(() => _savingBasic = true);
    try {
      final duration = int.tryParse(_durationController.text.trim()) ?? 0;
      if (_lessonId == null) {
        final id = await widget.service.createLesson(
          subjectId: widget.subjectId,
          title: title,
          description: _descController.text.trim(),
          duration: duration,
          orderNumber: widget.nextOrderNumber,
        );
        if (mounted) setState(() => _lessonId = id);
      } else {
        await widget.service.updateLesson(
          _lessonId!,
          title: title,
          description: _descController.text.trim(),
          duration: duration,
          pdfTitle: _pdfTitleController.text.trim(),
          pdfDescription: _pdfDescController.text.trim(),
        );
      }
      return true;
    } catch (e) {
      _toast('Failed to save lesson.');
      return false;
    } finally {
      if (mounted) setState(() => _savingBasic = false);
    }
  }

  Future<void> _onSaveDraft() async {
    final ok = await _saveBasicFields();
    if (ok) _toast('Saved as draft.');
  }

  Future<void> _onPublish() async {
    if (_videoUrl.isEmpty && _pdfUrl.isEmpty) {
      _toast('Add at least one video or PDF before publishing.');
      return;
    }
    final ok = await _saveBasicFields();
    if (!ok || _lessonId == null) return;
    setState(() => _publishing = true);
    try {
      await widget.service.publishLesson(_lessonId!);
      if (mounted) setState(() => _status = 'published');
      _toast('Lesson published.');
    } catch (e) {
      _toast('Failed to publish lesson.');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _onUnpublish() async {
    if (_lessonId == null) return;
    final ok = await _saveBasicFields();
    if (!ok) return;
    setState(() => _publishing = true);
    try {
      await widget.service.unpublishLesson(_lessonId!);
      if (mounted) setState(() => _status = 'draft');
      _toast('Lesson moved back to draft.');
    } catch (e) {
      _toast('Failed to unpublish lesson.');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _pickAndUploadVideo() async {
    if (_lessonId == null) {
      final ok = await _saveBasicFields();
      if (!ok) return;
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp4', 'mov']);
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    setState(() => _uploadingVideo = true);
    try {
      final url = await widget.service.uploadLessonVideo(_lessonId!, file);
      _disposeVideoPreview();
      if (mounted) {
        setState(() {
          _videoUrl = url;
          _videoSource = 'upload';
          _showVideoPreview = false;
        });
      }
      _toast('Video uploaded.');
    } catch (e) {
      _toast('Video upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _saveYoutubeUrl() async {
    final url = _youtubeController.text.trim();
    if (url.isEmpty) {
      _toast('Paste a YouTube URL first.');
      return;
    }
    if (_lessonId == null) {
      final ok = await _saveBasicFields();
      if (!ok) return;
    }
    setState(() => _uploadingVideo = true);
    try {
      await widget.service.updateLesson(_lessonId!, videoUrl: url, videoSource: 'youtube');
      _disposeVideoPreview();
      if (mounted) {
        setState(() {
          _videoUrl = url;
          _videoSource = 'youtube';
          _showVideoPreview = false;
        });
      }
      _toast('YouTube video saved.');
    } catch (e) {
      _toast('Failed to save YouTube URL.');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _removeVideo() async {
    if (_lessonId == null) {
      setState(() {
        _videoUrl = '';
        _youtubeController.clear();
      });
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove video?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.updateLesson(_lessonId!, videoUrl: '', videoSource: 'upload');
      _disposeVideoPreview();
      if (mounted) {
        setState(() {
          _videoUrl = '';
          _videoSource = 'upload';
          _youtubeController.clear();
          _showVideoPreview = false;
        });
      }
      _toast('Video removed.');
    } catch (e) {
      _toast('Failed to remove video.');
    }
  }

  Future<void> _pickAndUploadPdf() async {
    if (_lessonId == null) {
      final ok = await _saveBasicFields();
      if (!ok) return;
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    setState(() => _uploadingPdf = true);
    try {
      final url = await widget.service.uploadLessonPdf(_lessonId!, file);
      if (mounted) setState(() => _pdfUrl = url);
      _toast('PDF uploaded.');
    } catch (e) {
      _toast('PDF upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingPdf = false);
    }
  }

  Future<void> _removePdf() async {
    if (_lessonId == null) {
      setState(() {
        _pdfUrl = '';
        _pdfTitleController.clear();
        _pdfDescController.clear();
      });
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove PDF?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.updateLesson(_lessonId!, pdfUrl: '', pdfTitle: '', pdfDescription: '');
      if (mounted) {
        setState(() {
          _pdfUrl = '';
          _pdfTitleController.clear();
          _pdfDescController.clear();
        });
      }
      _toast('PDF removed.');
    } catch (e) {
      _toast('Failed to remove PDF.');
    }
  }

  Future<void> _previewVideo() async {
    if (_videoUrl.isEmpty) return;
    if (_videoSource == 'youtube') {
      final uri = Uri.tryParse(_videoUrl);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (_showVideoPreview) {
      setState(() => _showVideoPreview = false);
      return;
    }
    setState(() => _showVideoPreview = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(ApiConstants.resolveMediaUrl(_videoUrl)));
      await controller.initialize();
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
      );
      _videoController = controller;
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Could not preview this video.');
      if (mounted) setState(() => _showVideoPreview = false);
    }
  }

  void _previewPdf() {
    if (_pdfUrl.isEmpty) return;
    final title = _pdfTitleController.text.trim().isNotEmpty ? _pdfTitleController.text.trim() : _titleController.text.trim();
    context.push('/pdf-viewer', extra: {'url': ApiConstants.resolveMediaUrl(_pdfUrl), 'title': title});
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null && _lessonId == null;
    final resourcesUnlocked = _lessonId != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isNew ? 'New Lesson' : 'Edit Lesson',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, _lessonId != null),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: _titleController, autofocus: isNew, decoration: const InputDecoration(labelText: 'Title *')),
                    const SizedBox(height: 12),
                    TextField(controller: _descController, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
                    const SizedBox(height: 12),
                    TextField(controller: _durationController, decoration: const InputDecoration(labelText: 'Duration (minutes)'), keyboardType: TextInputType.number),

                    if (!resourcesUnlocked) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Text(
                          'Tap "Save Draft" below to unlock video and PDF options for this lesson.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ],

                    if (resourcesUnlocked) ...[
                      const SizedBox(height: 20),
                      const Text('Video', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'upload', label: Text('Upload Video'), icon: Icon(Icons.upload_file_rounded, size: 16)),
                          ButtonSegment(value: 'youtube', label: Text('YouTube URL'), icon: Icon(Icons.smart_display_outlined, size: 16)),
                        ],
                        selected: {_videoSource},
                        onSelectionChanged: (s) => setState(() => _videoSource = s.first),
                      ),
                      const SizedBox(height: 10),
                      if (_videoSource == 'upload') ...[
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _uploadingVideo ? null : _pickAndUploadVideo,
                              icon: _uploadingVideo
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(_videoUrl.isNotEmpty && _videoSource == 'upload' ? Icons.refresh_rounded : Icons.upload_file_rounded, size: 16),
                              label: Text(_videoUrl.isNotEmpty && _videoSource == 'upload' ? 'Replace Video' : 'Upload Video'),
                            ),
                          ],
                        ),
                      ] else ...[
                        TextField(
                          controller: _youtubeController,
                          decoration: const InputDecoration(labelText: 'YouTube URL', hintText: 'https://www.youtube.com/watch?v=...'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _uploadingVideo ? null : _saveYoutubeUrl,
                              icon: _uploadingVideo
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.link_rounded, size: 16),
                              label: Text(_videoUrl.isNotEmpty && _videoSource == 'youtube' ? 'Replace URL' : 'Save URL'),
                            ),
                          ],
                        ),
                      ],
                      if (_videoUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(onPressed: _previewVideo, icon: const Icon(Icons.play_circle_outline_rounded, size: 18), label: Text(_videoSource == 'youtube' ? 'Open on YouTube' : (_showVideoPreview ? 'Hide Preview' : 'Preview'))),
                            TextButton.icon(onPressed: _removeVideo, icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), label: const Text('Remove', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      ],
                      if (_showVideoPreview && _videoSource == 'upload') ...[
                        const SizedBox(height: 8),
                        _chewieController == null
                            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
                            : AspectRatio(aspectRatio: _chewieController!.aspectRatio ?? 16 / 9, child: Chewie(controller: _chewieController!)),
                      ],

                      const SizedBox(height: 20),
                      const Text('PDF Notes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      TextField(controller: _pdfTitleController, decoration: const InputDecoration(labelText: 'PDF Title')),
                      const SizedBox(height: 8),
                      TextField(controller: _pdfDescController, decoration: const InputDecoration(labelText: 'PDF Description'), maxLines: 2),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _uploadingPdf ? null : _pickAndUploadPdf,
                            icon: _uploadingPdf
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(_pdfUrl.isNotEmpty ? Icons.refresh_rounded : Icons.upload_file_rounded, size: 16),
                            label: Text(_pdfUrl.isNotEmpty ? 'Replace PDF' : 'Upload PDF'),
                          ),
                        ],
                      ),
                      if (_pdfUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(onPressed: _previewPdf, icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('Preview')),
                            TextButton.icon(onPressed: _removePdf, icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), label: const Text('Remove', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context, _lessonId != null), child: const Text('Close')),
                  const SizedBox(width: 4),
                  if (_status != 'published')
                    FilledButton.tonal(
                      onPressed: _savingBasic ? null : _onSaveDraft,
                      child: _savingBasic ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Draft'),
                    )
                  else
                    FilledButton.tonal(
                      onPressed: _savingBasic ? null : () => _saveBasicFields(),
                      child: _savingBasic ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Changes'),
                    ),
                  const SizedBox(width: 8),
                  if (resourcesUnlocked && _status == 'draft')
                    FilledButton(
                      onPressed: _publishing ? null : _onPublish,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
                      child: _publishing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Publish'),
                    ),
                  if (resourcesUnlocked && _status == 'published')
                    FilledButton(
                      onPressed: _publishing ? null : _onUnpublish,
                      style: FilledButton.styleFrom(backgroundColor: Colors.grey.shade700),
                      child: _publishing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Unpublish'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\screens\courses\lesson_management_screen.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\screens\courses\lesson_management_screen.dart"

# --- frontend/lib/screens/lessons/lesson_player_screen.dart ---
$content = @'
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/lesson_model.dart';
import '../../providers/lesson_provider.dart';
import '../../services/lesson_service.dart';
import '../../widgets/notes_widget.dart';
import '../../widgets/skeleton_box.dart';
import '../lesson_videos_screen.dart';

/// Full lesson player: optional video, AI-generated explanation/key
/// points/examples/practice questions/summary, a Quiz button, recommended
/// YouTube videos, PDF notes, Previous/Next navigation, and Mark Complete.
///
/// If a lesson has no video, this screen shows the lesson's educational
/// thumbnail with "Educational content available — read notes below"
/// instead of an error, per the "no placeholder video" content strategy.
class LessonPlayerScreen extends StatefulWidget {
  final int lessonId;

  const LessonPlayerScreen({super.key, required this.lessonId});

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  final LessonService _lessonService = LessonService();

  LessonModel? _lesson;
  bool _isLoading = true;
  String? _errorMessage;

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _loadLesson(widget.lessonId);
  }

  Future<void> _loadLesson(int lessonId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _disposeVideo();

    try {
      final lesson = await _lessonService.fetchLessonById(lessonId);
      // QA fix ("Missing mounted checks after async operations"): this
      // setState ran unconditionally right after an await - if the user
      // had already navigated away while the fetch was in flight, this
      // threw "setState() called after dispose()".
      if (!mounted) return;
      setState(() => _lesson = lesson);

      if (lesson.videoUrl.isNotEmpty && lesson.videoSource != 'youtube') {
        await _initVideo(ApiConstants.resolveMediaUrl(lesson.videoUrl));
      }

      // QA fix ("Missing mounted checks after async operations"): two
      // separate awaits sit inside this single mounted-guard - if the
      // widget got unmounted during loadNotes() (between the two
      // calls), loadAiContent() below would still run against a
      // disposed context. Re-checking mounted between them closes that
      // gap instead of only checking once at the top.
      if (mounted) {
        await context.read<LessonProvider>().loadNotes(lessonId);
        if (mounted) {
          await context.read<LessonProvider>().loadAiContent(lessonId);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Could not load this lesson. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initVideo(String url) async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
        errorBuilder: (context, errorMessage) => Center(
          child: Text(errorMessage, style: const TextStyle(color: Colors.white)),
        ),
      );
      _videoController = controller;
      if (mounted) setState(() {});
    } catch (e) {
      _videoController = null;
      _chewieController = null;
    }
  }

  void _disposeVideo() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  void _goToLesson(LessonModel? target) {
    if (target == null) return;
    _loadLesson(target.id);
  }

  @override
  Widget build(BuildContext context) {
    final lessonProvider = context.watch<LessonProvider>();
    final previous = _lesson != null ? lessonProvider.previousOf(_lesson!.id) : null;
    final next = _lesson != null ? lessonProvider.nextOf(_lesson!.id) : null;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(_lesson?.title ?? 'Lesson')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: () => _loadLesson(widget.lessonId), child: const Text('Retry')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: _buildMediaArea(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLessonHeaderCard(),
                            const SizedBox(height: 16),
                            _buildNavigationRow(previous, next),
                            const SizedBox(height: 12),
                            _buildMarkCompleteButton(),
                            const SizedBox(height: 24),
                            _buildAiContentSection(lessonProvider),
                            const SizedBox(height: 24),
                            _buildVideosSection(),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: AppTheme.softShadow,
                              ),
                              child: NotesWidget(
                                notes: lessonProvider.notes,
                                isLoading: lessonProvider.isLoadingNotes,
                                errorMessage: lessonProvider.notesErrorMessage,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Recommended Videos — sits between AI Explanation and PDF Notes.
  /// Does not touch AI content, notes, progress, or the video player above.
  Widget _buildVideosSection() {
    if (_lesson == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: LessonVideosScreen(
        lessonId: _lesson!.id,
        lessonTitle: _lesson!.title,
      ),
    );
  }

  Widget _buildLessonHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_lesson!.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time_rounded, size: 14, color: AppColors.purple),
                const SizedBox(width: 6),
                Text('${_lesson!.duration} minutes', style: const TextStyle(color: AppColors.purple, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (_lesson!.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            Text(_lesson!.description, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _buildNavigationRow(LessonModel? previous, LessonModel? next) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: previous != null ? () => _goToLesson(previous) : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.skip_previous_rounded),
            label: const Text('Previous'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: next != null ? () => _goToLesson(next) : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Next'),
          ),
        ),
      ],
    );
  }

  Widget _buildMarkCompleteButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          await context.read<LessonProvider>().markCompleted(_lesson!.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lesson marked as complete')),
            );
          }
        },
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          foregroundColor: AppColors.green,
          side: const BorderSide(color: AppColors.green),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.check_circle_outline_rounded),
        label: const Text('Mark Complete'),
      ),
    );
  }

  Widget _buildAiContentSection(LessonProvider provider) {
    if (provider.isLoadingAiContent) {
      return Column(
        children: [
          SkeletonBox(height: 24, width: 160, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 12),
          SkeletonBox(height: 100, borderRadius: BorderRadius.circular(16)),
        ],
      );
    }

    if (provider.aiContentUnavailable) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.softShadow,
        ),
        child: const Text(
          'AI-generated notes for this lesson are not available yet. Check the PDF notes below.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    if (provider.aiContentErrorMessage != null) {
      return Text(provider.aiContentErrorMessage!, style: const TextStyle(color: AppColors.error));
    }

    final content = provider.aiContent;
    if (content == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _aiCard('Explanation', Icons.lightbulb_outline_rounded, Text(content.explanation, style: const TextStyle(height: 1.5))),
        const SizedBox(height: 14),
        if (content.keyPoints.isNotEmpty)
          _aiCard(
            'Key Points',
            Icons.checklist_rounded,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.keyPoints.map((p) => _bullet(p)).toList(),
            ),
          ),
        const SizedBox(height: 14),
        if (content.examples.isNotEmpty)
          _aiCard(
            'Examples',
            Icons.school_outlined,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.examples.map((p) => _bullet(p)).toList(),
            ),
          ),
        const SizedBox(height: 14),
        if (content.practiceQuestions.isNotEmpty)
          _aiCard(
            'Practice Questions',
            Icons.edit_note_rounded,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.practiceQuestions.map((p) => _bullet(p)).toList(),
            ),
          ),
        const SizedBox(height: 14),
        _aiCard('Summary', Icons.summarize_outlined, Text(content.summary, style: const TextStyle(height: 1.5))),
        if (content.quiz.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/quiz', extra: {'lessonId': _lesson!.id, 'questions': content.quiz}),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.quiz_rounded),
              label: const Text('Take Quiz'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _aiCard(String title, IconData icon, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.purple),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildMediaArea() {
    if (_lesson != null && _lesson!.videoUrl.isNotEmpty && _lesson!.videoSource == 'youtube') {
      final thumb = _lesson?.thumbnailUrl ?? '';
      return GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(_lesson!.videoUrl);
          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: Container(
          height: 220,
          color: Colors.black12,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb.isNotEmpty)
                Image.network(
                  ApiConstants.resolveMediaUrl(thumb),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              Container(
                color: Colors.black.withOpacity(0.35),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 56),
                    SizedBox(height: 8),
                    Text('Watch on YouTube', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_lesson == null || _lesson!.videoUrl.isEmpty) {
      // No placeholder/cartoon video — show the lesson's educational
      // thumbnail (if any) with a message pointing to the notes below.
      final thumb = _lesson?.thumbnailUrl ?? '';
      return Container(
        height: 220,
        color: Colors.black12,
        child: thumb.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    ApiConstants.resolveMediaUrl(thumb),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                  Container(
                    color: Colors.black.withOpacity(0.35),
                    alignment: Alignment.center,
                    child: const Text(
                      'Educational content available\nRead notes below',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              )
            : const Center(
                child: Text(
                  'Educational content available\nRead notes below',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
      );
    }

    if (_chewieController == null) {
      return Container(
        height: 220,
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return AspectRatio(
      aspectRatio: _chewieController!.aspectRatio ?? 16 / 9,
      child: Chewie(controller: _chewieController!),
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\screens\lessons\lesson_player_screen.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\screens\lessons\lesson_player_screen.dart"

# --- frontend/lib/screens/courses/teacher_lessons_screen.dart ---
$content = @'
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/course_model.dart';
import '../../services/course_service.dart';
import 'lesson_management_screen.dart';

/// Teacher entry point for Lesson Resource Management: browse existing
/// courses (read-only - no add/delete/category actions, those stay
/// admin-only) and tap into a course to manage its lessons - create/
/// edit, upload video (or paste a YouTube URL), upload PDF notes, and
/// publish/unpublish. Reuses the exact same LessonManagementScreen the
/// admin panel uses, since the backend already accepts admin or teacher
/// for all lesson actions.
class TeacherLessonsScreen extends StatefulWidget {
  const TeacherLessonsScreen({super.key});

  @override
  State<TeacherLessonsScreen> createState() => _TeacherLessonsScreenState();
}

class _TeacherLessonsScreenState extends State<TeacherLessonsScreen> {
  final CourseService _service = CourseService();
  final TextEditingController _searchController = TextEditingController();

  List<AdminCourseModel> _courses = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _courses = await _service.listCourses(search: _searchController.text.trim());
    } catch (e) {
      _error = 'Could not load courses.';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Lessons')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search courses...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _courses.isEmpty
                        ? const Center(child: Text('No courses found yet.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: _courses.length,
                              itemBuilder: (context, index) => _courseCard(_courses[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _courseCard(AdminCourseModel course) {
    final isPublished = course.status == 'published';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonManagementScreen(courseId: course.id, courseName: course.name))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: course.thumbnail.isNotEmpty
                    ? Image.network(course.thumbnail, width: 64, height: 64, fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _thumbPlaceholder())
                    : _thumbPlaceholder(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(course.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPublished ? AppColors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isPublished ? 'Published' : 'Draft',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isPublished ? AppColors.green : Colors.orange),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(course.categoryName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.menu_book_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('${course.totalLessons} lessons', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      color: AppColors.purpleLight,
      child: const Icon(Icons.school_rounded, color: AppColors.purple, size: 26),
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\screens\courses\teacher_lessons_screen.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\screens\courses\teacher_lessons_screen.dart"

# --- frontend/lib/screens/profile/profile_screen.dart ---
$content = @'
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'edit_profile_screen.dart';
import '../badges/my_badges_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../leaderboard/manage_students_screen.dart';
import '../certificates/my_certificates_screen.dart';
import '../courses/admin_course_management_screen.dart';
import '../courses/teacher_lessons_screen.dart';

/// Profile tab: shows the logged-in user's info and a logout button.
/// UI redesign only â€” AuthProvider.logout() and the navigation after it
/// are exactly what they were before.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(color: AppColors.purpleLight, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      (user?.name.isNotEmpty == true ? user!.name[0] : '?').toUpperCase(),
                      style: const TextStyle(fontSize: 34, color: AppColors.purple, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(user?.name ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    (user?.role ?? '-').toUpperCase(),
                    style: const TextStyle(color: AppColors.purple, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),

          const SizedBox(height: 20),

          _ProfileMenuTile(
            icon: Icons.edit_outlined,
            label: 'Edit Profile',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
            },
          ).animate().fadeIn(duration: 250.ms, delay: 100.ms),
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.bar_chart_rounded,
            label: 'Quiz Analytics',
            onTap: () => context.push('/quiz-analytics'),
          ).animate().fadeIn(duration: 250.ms, delay: 130.ms),
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.auto_awesome_rounded,
            label: 'AI Quiz Generator',
            onTap: () => context.push('/ai-quiz-generator'),
          ).animate().fadeIn(duration: 250.ms, delay: 145.ms),
          _ProfileMenuTile(
            icon: Icons.leaderboard_rounded,
            label: 'Leaderboard',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
            },
          ).animate().fadeIn(duration: 250.ms, delay: 130.ms),
          if (auth.currentUser?.role == 'student') ...[
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.video_camera_front_rounded,
              label: 'Live Classes',
              onTap: () => context.push('/student-live-classes'),
            ).animate().fadeIn(duration: 250.ms, delay: 147.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.emoji_events_rounded,
              label: 'My Badges',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBadgesScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 160.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.workspace_premium_rounded,
              label: 'My Certificates',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCertificatesScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 165.ms),
          ],
          if (auth.currentUser?.role == 'teacher') ...[
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.assignment_rounded,
              label: 'My Assignments',
              onTap: () => context.push('/my-assignments'),
            ).animate().fadeIn(duration: 250.ms, delay: 148.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.video_camera_front_rounded,
              label: 'My Live Classes',
              onTap: () => context.push('/my-live-classes'),
            ).animate().fadeIn(duration: 250.ms, delay: 149.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.library_books_rounded,
              label: 'Manage Lessons',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherLessonsScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 150.ms),
          ],
          if (auth.currentUser?.role == 'admin') ...[
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.admin_panel_settings_rounded,
              label: 'Admin Panel',
              onTap: () => context.push('/admin-dashboard'),
            ).animate().fadeIn(duration: 250.ms, delay: 150.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.groups_rounded,
              label: 'Manage Students',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageStudentsScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 155.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.workspace_premium_rounded,
              label: 'All Certificates',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCertificatesScreen(mode: CertificateListMode.admin)));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 156.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.library_books_rounded,
              label: 'Course Management',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCourseManagementScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 157.ms),
          ],
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.logout_rounded,
            label: 'Logout',
            color: AppColors.error,
            onTap: () async {
              await context.read<AuthProvider>().logout();
              if (context.mounted) context.go('/login');
            },
          ).animate().fadeIn(duration: 250.ms, delay: 160.ms),
        ],
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ProfileMenuTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.textPrimary;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 22),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w600, fontSize: 15))),
              Icon(Icons.chevron_right_rounded, color: tint.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\screens\profile\profile_screen.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\screens\profile\profile_screen.dart"

Write-Host ""
Write-Host "All files written successfully." -ForegroundColor Green