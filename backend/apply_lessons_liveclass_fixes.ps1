# apply_lessons_liveclass_fixes.ps1
# Run from your backend project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\backend)
# Writes: lessons module (RowsAffected + info-leak fixes) and liveclass module
# (Asia/Kolkata timezone fix for missed/completed/attendance logic, RowsAffected,
# fixed Atoi error handling).
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying lessons/liveclass fixes in $root" -ForegroundColor Cyan

# --- internal/lessons/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/lessons") | Out-Null
$content_internal_lessons_repository_go = @'
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
//
// BUG FIX: was missing a rows.Err() check after the scan loop.
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
	if err := rows.Err(); err != nil {
		return nil, err
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
	// BUG FIX: was missing a rows.Err() check - a connection error mid-
	// iteration would silently truncate search results instead of
	// surfacing as an error.
	if err := rows.Err(); err != nil {
		return nil, err
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

// BUG FIX: didn't check RowsAffected. If lessonID doesn't exist (or was
// deleted between the upload starting and finishing), the Cloudinary
// upload still succeeded (wasting storage on an orphaned file) while
// this UPDATE silently matched 0 rows - the handler then reported
// "Video uploaded" with a URL attached to nothing.
func (r *Repository) SetVideoURL(id int, url string) error {
	// Direct file uploads always set video_source back to "upload" -
	// this is what distinguishes an uploaded file from a pasted
	// YouTube URL (set via Update) when the player decides how to
	// render the lesson's video.
	res, err := r.db.Exec(`UPDATE lessons SET video_url = $1, video_source = 'upload' WHERE id = $2`, url, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrLessonNotFound
	}
	return nil
}

func (r *Repository) SetPDFURL(id int, url string) error {
	res, err := r.db.Exec(`UPDATE lessons SET pdf_url = $1 WHERE id = $2`, url, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrLessonNotFound
	}
	return nil
}

func (r *Repository) SetAssignmentURL(id int, url string) error {
	res, err := r.db.Exec(`UPDATE lessons SET assignment_url = $1 WHERE id = $2`, url, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrLessonNotFound
	}
	return nil
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
[System.IO.File]::WriteAllText((Join-Path $root "internal/lessons/repository.go"), $content_internal_lessons_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/lessons/repository.go" -ForegroundColor Green

# --- internal/lessons/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/lessons") | Out-Null
$content_internal_lessons_handler_go = @'
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

	"ai-tutor-backend/internal/notes"
	"ai-tutor-backend/pkg/logger"
	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the lessons Service.
type Handler struct {
	service *Service
	// Lesson Resource Management (additive): kept in sync with a
	// lesson's pdf_url so students see it via the existing notes list.
	notesService *notes.Service
}

// NewHandler builds a lessons Handler around a Service.
func NewHandler(service *Service, notesService *notes.Service) *Handler {
	return &Handler{service: service, notesService: notesService}
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
		if isLessonValidationError(err) {
			utils.RespondError(c, http.StatusBadRequest, err.Error())
			return
		}
		logger.Error("lessons: Create failed", err)
		utils.RespondError(c, http.StatusBadRequest, "Could not create lesson - check that the subject exists")
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Lesson created", gin.H{"id": id})
}

// isLessonValidationError reports whether err is one of the plain input-
// validation errors Service.Create/Update return directly - these only
// ever describe the client's own input and are safe to show verbatim.
// Anything else (e.g. a foreign-key violation because subject_id doesn't
// exist) is a real DB error and must not be echoed to the client.
func isLessonValidationError(err error) bool {
	switch err.Error() {
	case "a valid subject_id is required", "lesson title is required":
		return true
	default:
		return false
	}
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
		if isLessonValidationError(err) {
			utils.RespondError(c, http.StatusBadRequest, err.Error())
			return
		}
		logger.Error("lessons: Update failed", err)
		utils.RespondError(c, http.StatusBadRequest, "Could not update lesson")
		return
	}
	// Lesson Resource Management (additive): if this request touched
	// the PDF (removing it, or editing its title/description), keep
	// the mirrored note in sync too.
	if req.PDFURL != nil || req.PDFTitle != nil || req.PDFDescription != nil {
		if lesson, err := h.service.GetByID(id); err == nil {
			h.syncNoteForLesson(id, lesson.PDFURL)
		}
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
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		logger.Error("lessons: UploadVideo failed", err)
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
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		logger.Error("lessons: UploadPDF failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to upload PDF")
		return
	}
	h.syncNoteForLesson(id, url)
	utils.RespondSuccess(c, http.StatusOK, "PDF uploaded", gin.H{"pdf_url": url})
}

// --- Lesson Resource Management (additive) ---

// syncNoteForLesson mirrors a lesson's pdf_url into the notes table so
// it shows up in the existing student-facing notes list. Best-effort:
// a failure here shouldn't fail the PDF upload/update/remove itself,
// so it's only logged, not returned as an error.
func (h *Handler) syncNoteForLesson(lessonID int, pdfURL string) {
	if h.notesService == nil {
		return
	}
	title := "Lesson Notes"
	if lesson, err := h.service.GetByID(lessonID); err == nil {
		if lesson.PDFTitle != "" {
			title = lesson.PDFTitle
		} else if lesson.Title != "" {
			title = lesson.Title
		}
	}
	if err := h.notesService.SyncForLesson(lessonID, title, pdfURL); err != nil {
		fmt.Printf("[lessons] failed to sync notes for lesson %d: %v\n", lessonID, err)
	}
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
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		logger.Error("lessons: UploadAssignment failed", err)
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
[System.IO.File]::WriteAllText((Join-Path $root "internal/lessons/handler.go"), $content_internal_lessons_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/lessons/handler.go" -ForegroundColor Green

# --- internal/liveclass/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/liveclass") | Out-Null
$content_internal_liveclass_repository_go = @'
package liveclass

import (
	"database/sql"
	"errors"
)

var ErrNotFound = errors.New("live class not found")
var ErrForbidden = errors.New("you don't have permission to do that")

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(teacherID int, req CreateRequest) (int, error) {
	var lessonID interface{}
	if req.LessonID > 0 {
		lessonID = req.LessonID
	}
	var maxStudents interface{}
	if req.MaxStudents > 0 {
		maxStudents = req.MaxStudents
	}
	var password interface{}
	if req.MeetingPassword != "" {
		password = req.MeetingPassword
	}

	var id int
	err := r.db.QueryRow(`
		INSERT INTO live_classes (teacher_id, subject_id, lesson_id, title, description, class_date, start_time, end_time, max_students, is_public, meeting_password, record_class, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'scheduled')
		RETURNING id`,
		teacherID, req.SubjectID, lessonID, req.Title, req.Description, req.ClassDate, req.StartTime, req.EndTime,
		maxStudents, req.IsPublic, password, req.RecordClass,
	).Scan(&id)
	return id, err
}

func (r *Repository) checkOwnership(classID, teacherID int) error {
	var ownerID int
	err := r.db.QueryRow(`SELECT teacher_id FROM live_classes WHERE id = $1`, classID).Scan(&ownerID)
	if err == sql.ErrNoRows {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if ownerID != teacherID {
		return ErrForbidden
	}
	return nil
}

func (r *Repository) Update(classID, teacherID int, req UpdateRequest) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`
		UPDATE live_classes SET
			title = COALESCE($1, title),
			description = COALESCE($2, description),
			class_date = COALESCE($3, class_date),
			start_time = COALESCE($4, start_time),
			end_time = COALESCE($5, end_time),
			max_students = COALESCE($6, max_students),
			is_public = COALESCE($7, is_public),
			meeting_password = COALESCE($8, meeting_password),
			record_class = COALESCE($9, record_class),
			updated_at = now()
		WHERE id = $10`,
		req.Title, req.Description, req.ClassDate, req.StartTime, req.EndTime,
		req.MaxStudents, req.IsPublic, req.MeetingPassword, req.RecordClass, classID,
	)
	return err
}

func (r *Repository) SetStatus(classID, teacherID int, status string) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`UPDATE live_classes SET status = $1, updated_at = now() WHERE id = $2`, status, classID)
	return err
}

// AdminCancel bypasses the teacher-ownership check - admin can cancel
// any class platform-wide.
func (r *Repository) AdminCancel(classID int) error {
	res, err := r.db.Exec(`UPDATE live_classes SET status = $1, updated_at = now() WHERE id = $2`, StatusCancelled, classID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// SetMeetingLive records that the teacher started the video session -
// ownership-checked.
func (r *Repository) SetMeetingLive(classID, teacherID int, roomName string) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`
		UPDATE live_classes SET room_name = $1, meeting_status = $2, started_at = now(), updated_at = now()
		WHERE id = $3`, roomName, MeetingLive, classID)
	return err
}

// SetMeetingEnded records that the teacher ended the video session -
// ownership-checked.
func (r *Repository) SetMeetingEnded(classID, teacherID int) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`
		UPDATE live_classes SET meeting_status = $1, ended_at = now(), updated_at = now()
		WHERE id = $2`, MeetingEnded, classID)
	return err
}

func (r *Repository) Delete(classID, teacherID int) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`DELETE FROM live_classes WHERE id = $1`, classID)
	return err
}

// computedStatusExpr turns a stored 'scheduled' row into 'missed' once its
// end time has passed, without needing a background job.
//
// BUG FIX (timezone mismatch): class_date/start_time/end_time are plain
// DATE/TIME columns with no timezone attached (see migration 016).
// `(lc.class_date + lc.end_time)` is therefore a TIMESTAMP WITHOUT TIME
// ZONE, and comparing it directly to now() (TIMESTAMPTZ) makes Postgres
// implicitly interpret that naive timestamp using the DB SESSION's
// configured timezone - which may or may not match the timezone
// teachers actually schedule classes in. If the session defaults to UTC
// while class times are entered in India Standard Time (this app's
// target audience), "missed"/"completed" status and attendance windows
// would be off by 5.5 hours. `AT TIME ZONE 'Asia/Kolkata'` makes the
// interpretation explicit instead of relying on whatever the session
// happens to be set to. If your deployment's teachers/students are in a
// different timezone, change this literal to match.
const computedStatusExpr = `
	CASE WHEN lc.status = 'scheduled' AND lc.meeting_status != 'live'
	     AND ((lc.class_date + lc.end_time) AT TIME ZONE 'Asia/Kolkata') < now()
	THEN 'missed' ELSE lc.status END
`

const liveClassSelect = `
	SELECT lc.id, lc.teacher_id, u.name, lc.subject_id, COALESCE(s.name, ''), lc.lesson_id, COALESCE(l.title, ''),
	       lc.title, lc.description, lc.class_date::text, lc.start_time::text, lc.end_time::text,
	       lc.max_students, lc.is_public, (lc.meeting_password IS NOT NULL), lc.record_class,
	       ` + computedStatusExpr + `, COALESCE(lc.room_name, ''), lc.meeting_status, lc.locked, lc.started_at, lc.ended_at, lc.created_at
	FROM live_classes lc
	JOIN users u ON u.id = lc.teacher_id
	LEFT JOIN subjects s ON s.id = lc.subject_id
	LEFT JOIN lessons l ON l.id = lc.lesson_id
`

func scanLiveClass(row interface{ Scan(...any) error }) (LiveClass, error) {
	var c LiveClass
	var subjectID, lessonID sql.NullInt64
	var subjectName, lessonTitle sql.NullString
	var maxStudents sql.NullInt64
	err := row.Scan(
		&c.ID, &c.TeacherID, &c.TeacherName, &subjectID, &subjectName, &lessonID, &lessonTitle,
		&c.Title, &c.Description, &c.ClassDate, &c.StartTime, &c.EndTime,
		&maxStudents, &c.IsPublic, &c.HasPassword, &c.RecordClass, &c.Status,
		&c.RoomName, &c.MeetingStatus, &c.Locked, &c.StartedAt, &c.EndedAt, &c.CreatedAt,
	)
	if subjectID.Valid {
		id := int(subjectID.Int64)
		c.SubjectID = &id
	}
	c.SubjectName = subjectName.String
	if lessonID.Valid {
		id := int(lessonID.Int64)
		c.LessonID = &id
	}
	c.LessonTitle = lessonTitle.String
	if maxStudents.Valid {
		v := int(maxStudents.Int64)
		c.MaxStudents = &v
	}
	return c, err
}

func (r *Repository) GetByID(classID int) (*LiveClass, error) {
	row := r.db.QueryRow(liveClassSelect+` WHERE lc.id = $1`, classID)
	c, err := scanLiveClass(row)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *Repository) ListForTeacher(teacherID int) ([]LiveClass, error) {
	rows, err := r.db.Query(liveClassSelect+` WHERE lc.teacher_id = $1 ORDER BY lc.class_date DESC, lc.start_time DESC`, teacherID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanLiveClassRows(rows)
}

// ListForStudent returns every class (open access, matching how subjects/
// lessons/assignments already work in this app - no enrollment gate).
func (r *Repository) ListForStudent() ([]LiveClass, error) {
	rows, err := r.db.Query(liveClassSelect + ` WHERE lc.is_public = true ORDER BY lc.class_date DESC, lc.start_time DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanLiveClassRows(rows)
}

func (r *Repository) ListAllForAdmin() ([]LiveClass, error) {
	rows, err := r.db.Query(liveClassSelect + ` ORDER BY lc.class_date DESC, lc.start_time DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanLiveClassRows(rows)
}

func scanLiveClassRows(rows *sql.Rows) ([]LiveClass, error) {
	var result []LiveClass
	for rows.Next() {
		c, err := scanLiveClass(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, c)
	}
	return result, rows.Err()
}

func (r *Repository) GetUserName(userID int) (string, error) {
	var name string
	err := r.db.QueryRow(`SELECT name FROM users WHERE id = $1`, userID).Scan(&name)
	return name, err
}

// SetLocked toggles whether new students can join - ownership-checked.
func (r *Repository) SetLocked(classID, teacherID int, locked bool) error {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`UPDATE live_classes SET locked = $1, updated_at = now() WHERE id = $2`, locked, classID)
	return err
}

// --- Attendance (self check-in) ---

// CheckIn records studentID as present/late for classID. Only allowed
// while the class's scheduled window is open (enforced in the service
// layer, which knows "now" vs the class's start/end time).
func (r *Repository) CheckIn(classID, studentID int, status string) error {
	_, err := r.db.Exec(`
		INSERT INTO live_class_attendance (live_class_id, student_id, status)
		VALUES ($1, $2, $3)
		ON CONFLICT (live_class_id, student_id) DO NOTHING`,
		classID, studentID, status,
	)
	return err
}

func (r *Repository) GetMyAttendance(classID, studentID int) (*AttendanceRecord, error) {
	var rec AttendanceRecord
	err := r.db.QueryRow(`
		SELECT student_id, checked_in_at, status FROM live_class_attendance
		WHERE live_class_id = $1 AND student_id = $2`, classID, studentID,
	).Scan(&rec.StudentID, &rec.CheckedInAt, &rec.Status)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &rec, nil
}

// ListAttendanceForClass is for the teacher - who checked in, and when.
// Ownership-checked: only the class's own teacher can see it.
func (r *Repository) ListAttendanceForClass(classID, teacherID int) ([]AttendanceRecord, error) {
	if err := r.checkOwnership(classID, teacherID); err != nil {
		return nil, err
	}
	rows, err := r.db.Query(`
		SELECT a.student_id, u.name, a.checked_in_at, a.status
		FROM live_class_attendance a
		JOIN users u ON u.id = a.student_id
		WHERE a.live_class_id = $1
		ORDER BY a.checked_in_at ASC`, classID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []AttendanceRecord
	for rows.Next() {
		var rec AttendanceRecord
		if err := rows.Scan(&rec.StudentID, &rec.StudentName, &rec.CheckedInAt, &rec.Status); err != nil {
			return nil, err
		}
		result = append(result, rec)
	}
	return result, rows.Err()
}

// GetAttendanceSummaryForStudent: attendance % across every class that
// has already ended (completed/missed) - the honest denominator, since
// there's no per-class enrollment to know who was "supposed" to attend.
//
// BUG FIX (timezone mismatch): same reasoning as computedStatusExpr above -
// `AT TIME ZONE 'Asia/Kolkata'` makes the DATE+TIME -> instant conversion
// explicit instead of depending on the DB session's timezone setting.
func (r *Repository) GetAttendanceSummaryForStudent(studentID int) (*AttendanceSummary, error) {
	summary := &AttendanceSummary{}

	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM live_classes
		WHERE status = 'completed' OR (status = 'scheduled' AND ((class_date + end_time) AT TIME ZONE 'Asia/Kolkata') < now())
	`).Scan(&summary.TotalCompletedClasses)
	if err != nil {
		return nil, err
	}

	err = r.db.QueryRow(`
		SELECT COUNT(*) FROM live_class_attendance a
		JOIN live_classes lc ON lc.id = a.live_class_id
		WHERE a.student_id = $1
		AND (lc.status = 'completed' OR (lc.status = 'scheduled' AND ((lc.class_date + lc.end_time) AT TIME ZONE 'Asia/Kolkata') < now()))
	`, studentID).Scan(&summary.AttendedCount)
	if err != nil {
		return nil, err
	}

	if summary.TotalCompletedClasses > 0 {
		summary.Percentage = (float64(summary.AttendedCount) / float64(summary.TotalCompletedClasses)) * 100
	}
	return summary, nil
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/liveclass/repository.go"), $content_internal_liveclass_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/liveclass/repository.go" -ForegroundColor Green

# --- internal/liveclass/service.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/liveclass") | Out-Null
$content_internal_liveclass_service_go = @'
package liveclass

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"ai-tutor-backend/internal/badge"
	"ai-tutor-backend/internal/livekit"
	"ai-tutor-backend/internal/notification"
)

// ErrInvalidTimeRange is returned when a class's end time is not after
// its start time (QA fix: "Validate End Time > Start Time" - this was
// never checked at all, so a class could be scheduled with an end time
// before or equal to its start time).
var ErrInvalidTimeRange = errors.New("end time must be after start time")

type Service struct {
	repo            *Repository
	notificationSvc *notification.Service
	tokenSvc        *livekit.TokenService
	roomClient      *livekit.RoomClient
	livekitURL      string
	badgeSvc        *badge.Service
}

func NewService(repo *Repository, notificationSvc *notification.Service, tokenSvc *livekit.TokenService, roomClient *livekit.RoomClient, livekitURL string, badgeSvc *badge.Service) *Service {
	return &Service{repo: repo, notificationSvc: notificationSvc, tokenSvc: tokenSvc, roomClient: roomClient, livekitURL: livekitURL, badgeSvc: badgeSvc}
}

// validateTimeRange parses "HH:MM" start/end strings and confirms end
// is strictly after start. Invalid/unparseable times are left for the
// existing required-field validation to catch elsewhere - this only
// rejects a well-formed but backwards range.
func validateTimeRange(startTime, endTime string) error {
	start := parseTimeParts(startTime)
	end := parseTimeParts(endTime)
	if start == nil || end == nil {
		return nil
	}
	startMinutes := start[0]*60 + start[1]
	endMinutes := end[0]*60 + end[1]
	if endMinutes <= startMinutes {
		return ErrInvalidTimeRange
	}
	return nil
}

func (s *Service) Create(teacherID int, req CreateRequest) (int, error) {
	if err := validateTimeRange(req.StartTime, req.EndTime); err != nil {
		return 0, err
	}

	// The "Public" toggle has been removed from the schedule form - every
	// class stays visible to students by default (unchanged existing
	// behavior), regardless of what the client sends for this field.
	req.IsPublic = true

	id, err := s.repo.Create(teacherID, req)
	if err != nil {
		return 0, err
	}
	_ = s.notificationSvc.NotifyAllStudents(
		notification.TypeNewLiveClass,
		"New Live Class Scheduled",
		fmt.Sprintf("%s on %s at %s", req.Title, req.ClassDate, req.StartTime),
		id,
	) // best-effort
	return id, nil
}

func (s *Service) Update(classID, teacherID int, req UpdateRequest) error {
	if req.StartTime != nil && req.EndTime != nil {
		if err := validateTimeRange(*req.StartTime, *req.EndTime); err != nil {
			return err
		}
	}
	return s.repo.Update(classID, teacherID, req)
}

func (s *Service) Cancel(classID, teacherID int) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if err := s.repo.SetStatus(classID, teacherID, StatusCancelled); err != nil {
		return err
	}
	_ = s.notificationSvc.NotifyAllStudents(
		notification.TypeLiveClassCancelled,
		"Live Class Cancelled",
		fmt.Sprintf("%s on %s has been cancelled", class.Title, class.ClassDate),
		classID,
	) // best-effort
	return nil
}

func (s *Service) AdminCancel(classID int) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if err := s.repo.AdminCancel(classID); err != nil {
		return err
	}
	_ = s.notificationSvc.NotifyAllStudents(
		notification.TypeLiveClassCancelled,
		"Live Class Cancelled",
		fmt.Sprintf("%s on %s has been cancelled", class.Title, class.ClassDate),
		classID,
	) // best-effort
	return nil
}

func (s *Service) MarkCompleted(classID, teacherID int) error {
	return s.repo.SetStatus(classID, teacherID, StatusCompleted)
}

func (s *Service) Delete(classID, teacherID int) error {
	return s.repo.Delete(classID, teacherID)
}

func (s *Service) GetByID(classID int) (*LiveClass, error) {
	return s.repo.GetByID(classID)
}

func (s *Service) ListForTeacher(teacherID int) ([]LiveClass, error) {
	return s.repo.ListForTeacher(teacherID)
}

func (s *Service) ListForStudent() ([]LiveClass, error) {
	return s.repo.ListForStudent()
}

func (s *Service) ListAllForAdmin() ([]LiveClass, error) {
	return s.repo.ListAllForAdmin()
}

// --- Real video session (LiveKit) ---

var ErrMeetingNotLive = fmt.Errorf("the teacher hasn't started this class yet")
var ErrMeetingAlreadyEnded = fmt.Errorf("this class has already ended")

func (s *Service) Start(classID, teacherID int) (*StartResponse, error) {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return nil, err
	}
	if class.TeacherID != teacherID {
		return nil, ErrForbidden
	}
	if class.MeetingStatus == MeetingEnded {
		return nil, ErrMeetingAlreadyEnded
	}
	// QA fix: cancelling a class only ever set the schedule Status to
	// "cancelled" - it never blocked Start() from also flipping
	// MeetingStatus to "live", since Start() only checked MeetingStatus.
	// A cancelled class could still be started and joined.
	if class.Status == StatusCancelled {
		return nil, ErrClassCancelled
	}

	roomName := class.RoomName
	if roomName == "" {
		roomName = fmt.Sprintf("class-%d", classID)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := s.roomClient.EnsureRoom(ctx, roomName); err != nil {
		log.Printf("[liveclass] EnsureRoom failed for room %q: %v", roomName, err)
		return nil, fmt.Errorf("could not reach LiveKit: %w", err)
	}

	if err := s.repo.SetMeetingLive(classID, teacherID, roomName); err != nil {
		log.Printf("[liveclass] SetMeetingLive DB update failed for class %d: %v", classID, err)
		return nil, err
	}

	teacherName, _ := s.repo.GetUserName(teacherID)
	token, err := s.tokenSvc.GenerateToken(roomName, fmt.Sprintf("teacher-%d", teacherID), teacherName, true)
	if err != nil {
		log.Printf("[liveclass] GenerateToken failed for teacher %d: %v", teacherID, err)
		return nil, err
	}

	return &StartResponse{Token: token, URL: s.livekitURL, RoomName: roomName}, nil
}

var ErrRoomLocked = fmt.Errorf("the teacher has locked this class to new joins")

func (s *Service) Join(classID, studentID int) (*JoinResponse, error) {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return nil, err
	}
	if class.MeetingStatus != MeetingLive {
		return nil, ErrMeetingNotLive
	}
	if class.Locked {
		return nil, ErrRoomLocked
	}

	if class.MaxStudents != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		participants, err := s.roomClient.ListParticipants(ctx, class.RoomName)
		cancel()
		if err == nil {
			teacherIdentity := fmt.Sprintf("teacher-%d", class.TeacherID)
			studentCount := 0
			for _, p := range participants {
				if p.Identity != teacherIdentity {
					studentCount++
				}
			}
			if studentCount >= *class.MaxStudents {
				return nil, ErrClassFull
			}
		}
		// If the LiveKit call itself fails, we deliberately don't block the
		// join on that - the capacity check is a nice-to-have, not a
		// reason to hard-fail joining over an unrelated infra hiccup.
	}

	studentName, _ := s.repo.GetUserName(studentID)
	token, err := s.tokenSvc.GenerateToken(class.RoomName, fmt.Sprintf("student-%d", studentID), studentName, false)
	if err != nil {
		return nil, err
	}

	_ = s.repo.CheckIn(classID, studentID, AttendancePresent) // best-effort, real join = present
	go s.badgeSvc.CheckAndAwardBadges(studentID)

	return &JoinResponse{Token: token, URL: s.livekitURL, RoomName: class.RoomName}, nil
}

func (s *Service) End(classID, teacherID int) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if class.TeacherID != teacherID {
		return ErrForbidden
	}

	if class.RoomName != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = s.roomClient.EndRoom(ctx, class.RoomName) // best-effort - still mark ended even if this fails
	}

	if err := s.repo.SetMeetingEnded(classID, teacherID); err != nil {
		return err
	}

	// meeting_status and status (scheduled/completed) are separate
	// columns - without also completing the schedule status here, the
	// class stayed in "Upcoming" (Join/I'm Present buttons still shown)
	// forever after the meeting genuinely ended. Ending the meeting is
	// exactly the "class is done" signal - it should always land in
	// Past Classes, so a teacher never needs a second manual step, and
	// this ALSO doubles as the "teacher cannot reopen the same meeting"
	// guard (Start() already refuses once status leaves 'scheduled').
	return s.repo.SetStatus(classID, teacherID, StatusCompleted)
}

func (s *Service) GetMeetingStatus(classID int) (string, error) {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return "", err
	}
	return class.MeetingStatus, nil
}

// --- Teacher moderation ---

func (s *Service) MuteParticipant(classID, teacherID int, targetIdentity string) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if class.TeacherID != teacherID {
		return ErrForbidden
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return s.roomClient.MuteParticipant(ctx, class.RoomName, targetIdentity)
}

func (s *Service) RemoveParticipant(classID, teacherID int, targetIdentity string) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if class.TeacherID != teacherID {
		return ErrForbidden
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return s.roomClient.RemoveParticipant(ctx, class.RoomName, targetIdentity)
}

func (s *Service) MuteAll(classID, teacherID int) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if class.TeacherID != teacherID {
		return ErrForbidden
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return s.roomClient.MuteAllExcept(ctx, class.RoomName, fmt.Sprintf("teacher-%d", teacherID))
}

func (s *Service) SetLocked(classID, teacherID int, locked bool) error {
	return s.repo.SetLocked(classID, teacherID, locked)
}

// --- Attendance ---

var ErrAttendanceWindowClosed = fmt.Errorf("check-in is only available during the scheduled class time")

// BUG FIX (timezone mismatch): used to build start/end from
// time.Now().Location() - the Go process's local timezone, which
// depends entirely on the container/OS's TZ setting (typically UTC by
// default and easy to get out of sync with the database side). That
// meant this Go-side "is check-in open" window could silently disagree
// with the SQL-side computedStatusExpr/GetAttendanceSummaryForStudent
// (repository.go), which now explicitly use Asia/Kolkata. Using the same
// explicit zone here keeps both halves of "when did/does this class
// happen" consistent with each other and with the app's actual (India-
// based) users, regardless of what timezone the server process itself
// happens to be running in.
var istLocation = mustLoadIST()

func mustLoadIST() *time.Location {
	loc, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("[liveclass] failed to load Asia/Kolkata timezone, falling back to UTC: %v", err)
		return time.UTC
	}
	return loc
}

func (s *Service) CheckIn(classID, studentID int) (string, error) {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return "", err
	}

	dateParts := parseDateParts(class.ClassDate)
	startParts := parseTimeParts(class.StartTime)
	endParts := parseTimeParts(class.EndTime)
	if dateParts == nil || startParts == nil || endParts == nil {
		return "", fmt.Errorf("invalid class schedule data")
	}

	start := time.Date(dateParts[0], time.Month(dateParts[1]), dateParts[2], startParts[0], startParts[1], 0, 0, istLocation)
	end := time.Date(dateParts[0], time.Month(dateParts[1]), dateParts[2], endParts[0], endParts[1], 0, 0, istLocation)
	now := time.Now().In(istLocation)

	if now.Before(start) || now.After(end) {
		return "", ErrAttendanceWindowClosed
	}

	status := AttendancePresent
	if now.After(start.Add(10 * time.Minute)) {
		status = AttendanceLate
	}

	if err := s.repo.CheckIn(classID, studentID, status); err != nil {
		return "", err
	}
	go s.badgeSvc.CheckAndAwardBadges(studentID)
	return status, nil
}

func parseDateParts(s string) []int {
	var y, m, d int
	if _, err := fmt.Sscanf(s, "%d-%d-%d", &y, &m, &d); err != nil {
		return nil
	}
	return []int{y, m, d}
}

func parseTimeParts(s string) []int {
	var h, m int
	if _, err := fmt.Sscanf(s, "%d:%d", &h, &m); err != nil {
		return nil
	}
	return []int{h, m}
}

func (s *Service) GetMyAttendance(classID, studentID int) (*MyAttendance, error) {
	rec, err := s.repo.GetMyAttendance(classID, studentID)
	if err != nil {
		return nil, err
	}
	if rec == nil {
		return &MyAttendance{CheckedIn: false}, nil
	}
	return &MyAttendance{CheckedIn: true, Status: rec.Status, CheckedInAt: &rec.CheckedInAt}, nil
}

func (s *Service) ListAttendanceForClass(classID, teacherID int) ([]AttendanceRecord, error) {
	return s.repo.ListAttendanceForClass(classID, teacherID)
}

func (s *Service) GetAttendanceSummaryForStudent(studentID int) (*AttendanceSummary, error) {
	return s.repo.GetAttendanceSummaryForStudent(studentID)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/liveclass/service.go"), $content_internal_liveclass_service_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/liveclass/service.go" -ForegroundColor Green

# --- internal/liveclass/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/liveclass") | Out-Null
$content_internal_liveclass_handler_go = @'
package liveclass

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func respondForError(c *gin.Context, err error, fallback string) {
	switch {
	case errors.Is(err, ErrNotFound):
		utils.RespondError(c, http.StatusNotFound, "Class not found")
	case errors.Is(err, ErrForbidden):
		utils.RespondError(c, http.StatusForbidden, "You can only manage classes you scheduled")
	case errors.Is(err, ErrInvalidTimeRange):
		utils.RespondError(c, http.StatusBadRequest, "End time must be after start time")
	default:
		utils.RespondError(c, http.StatusInternalServerError, fallback)
	}
}

func (h *Handler) Create(c *gin.Context) {
	var req CreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "subject_id, title, class_date, start_time, end_time, and max_students (at least 1) are required")
		return
	}
	teacherID := c.GetInt("user_id")
	id, err := h.service.Create(teacherID, req)
	if err != nil {
		if errors.Is(err, ErrInvalidTimeRange) {
			utils.RespondError(c, http.StatusBadRequest, "End time must be after start time")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to schedule class")
		return
	}
	utils.RespondSuccess(c, http.StatusCreated, "Class scheduled", gin.H{"id": id})
}

func (h *Handler) Update(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	var req UpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.Update(id, teacherID, req); err != nil {
		respondForError(c, err, "Failed to update class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class updated", nil)
}

func (h *Handler) Cancel(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.Cancel(id, teacherID); err != nil {
		respondForError(c, err, "Failed to cancel class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class cancelled", nil)
}

func (h *Handler) MarkCompleted(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.MarkCompleted(id, teacherID); err != nil {
		respondForError(c, err, "Failed to update class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class marked completed", nil)
}

func (h *Handler) Delete(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.Delete(id, teacherID); err != nil {
		respondForError(c, err, "Failed to delete class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class deleted", nil)
}

func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	class, err := h.service.GetByID(id)
	if err != nil {
		respondForError(c, err, "Failed to load class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class fetched", class)
}

func (h *Handler) ListMine(c *gin.Context) {
	teacherID := c.GetInt("user_id")
	list, err := h.service.ListForTeacher(teacherID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load classes")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Classes fetched", list)
}

func (h *Handler) ListForStudent(c *gin.Context) {
	list, err := h.service.ListForStudent()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load classes")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Classes fetched", list)
}

func (h *Handler) ListAllForAdmin(c *gin.Context) {
	list, err := h.service.ListAllForAdmin()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load classes")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Classes fetched", list)
}

// AdminCancel handles POST /api/admin/live-classes/:id/cancel.
func (h *Handler) AdminCancel(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	if err := h.service.AdminCancel(id); err != nil {
		respondForError(c, err, "Failed to cancel class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class cancelled", nil)
}

// CheckIn handles POST /api/live-classes/:id/check-in (student self
// attendance).
func (h *Handler) CheckIn(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	studentID := c.GetInt("user_id")
	status, err := h.service.CheckIn(id, studentID)
	if err != nil {
		if errors.Is(err, ErrAttendanceWindowClosed) {
			utils.RespondError(c, http.StatusConflict, "Check-in is only available during the scheduled class time")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to check in")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Checked in", gin.H{"status": status})
}

// GetMyAttendance handles GET /api/live-classes/:id/my-attendance.
func (h *Handler) GetMyAttendance(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	studentID := c.GetInt("user_id")
	att, err := h.service.GetMyAttendance(id, studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load attendance")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attendance fetched", att)
}

// ListAttendance handles GET /api/live-classes/:id/attendance (teacher).
func (h *Handler) ListAttendance(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	list, err := h.service.ListAttendanceForClass(id, teacherID)
	if err != nil {
		respondForError(c, err, "Failed to load attendance")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attendance fetched", list)
}

// AttendanceSummary handles GET /api/live-classes/attendance-summary (student).
func (h *Handler) AttendanceSummary(c *gin.Context) {
	studentID := c.GetInt("user_id")
	summary, err := h.service.GetAttendanceSummaryForStudent(studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load attendance summary")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Summary fetched", summary)
}

// --- Real video session (LiveKit) ---

// Start handles POST /api/live-classes/:id/start (teacher).
func (h *Handler) Start(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	result, err := h.service.Start(id, teacherID)
	if err != nil {
		respondForMeetingError(c, err, "Failed to start class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class started", result)
}

// Join handles POST /api/live-classes/:id/join (student).
func (h *Handler) Join(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	studentID := c.GetInt("user_id")
	result, err := h.service.Join(id, studentID)
	if err != nil {
		respondForMeetingError(c, err, "Failed to join class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Joined class", result)
}

// End handles POST /api/live-classes/:id/end (teacher).
func (h *Handler) End(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.End(id, teacherID); err != nil {
		respondForMeetingError(c, err, "Failed to end class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class ended", nil)
}

// MeetingStatus handles GET /api/live-classes/:id/meeting-status (anyone -
// students poll this to know when to enable their Join button).
func (h *Handler) MeetingStatus(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	status, err := h.service.GetMeetingStatus(id)
	if err != nil {
		respondForError(c, err, "Failed to load meeting status")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Status fetched", gin.H{"meeting_status": status})
}

// --- Teacher moderation ---

// MuteParticipant handles POST /api/live-classes/:id/mute/:identity.
func (h *Handler) MuteParticipant(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	identity := c.Param("identity")
	teacherID := c.GetInt("user_id")
	if err := h.service.MuteParticipant(id, teacherID, identity); err != nil {
		respondForMeetingError(c, err, "Failed to mute participant")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Participant muted", nil)
}

// RemoveParticipant handles POST /api/live-classes/:id/remove/:identity.
func (h *Handler) RemoveParticipant(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	identity := c.Param("identity")
	teacherID := c.GetInt("user_id")
	if err := h.service.RemoveParticipant(id, teacherID, identity); err != nil {
		respondForMeetingError(c, err, "Failed to remove participant")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Participant removed", nil)
}

// MuteAll handles POST /api/live-classes/:id/mute-all.
func (h *Handler) MuteAll(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.MuteAll(id, teacherID); err != nil {
		respondForMeetingError(c, err, "Failed to mute all participants")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "All participants muted", nil)
}

// Lock handles POST /api/live-classes/:id/lock.
func (h *Handler) Lock(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.SetLocked(id, teacherID, true); err != nil {
		respondForMeetingError(c, err, "Failed to lock class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class locked", nil)
}

// Unlock handles POST /api/live-classes/:id/unlock.
func (h *Handler) Unlock(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.SetLocked(id, teacherID, false); err != nil {
		respondForMeetingError(c, err, "Failed to unlock class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class unlocked", nil)
}

func respondForMeetingError(c *gin.Context, err error, fallback string) {
	switch {
	case errors.Is(err, ErrNotFound):
		utils.RespondError(c, http.StatusNotFound, "Class not found")
	case errors.Is(err, ErrForbidden):
		utils.RespondError(c, http.StatusForbidden, "You can only manage classes you scheduled")
	case errors.Is(err, ErrMeetingNotLive):
		utils.RespondError(c, http.StatusConflict, "The teacher hasn't started this class yet")
	case errors.Is(err, ErrMeetingAlreadyEnded):
		utils.RespondError(c, http.StatusConflict, "This class has already ended")
	case errors.Is(err, ErrRoomLocked):
		utils.RespondError(c, http.StatusForbidden, "The teacher has locked this class to new joins")
	case errors.Is(err, ErrClassFull):
		utils.RespondError(c, http.StatusConflict, "Class is full. Maximum participant limit reached.")
	case errors.Is(err, ErrClassCancelled):
		utils.RespondError(c, http.StatusConflict, "This class has been cancelled and cannot be started")
	default:
		utils.RespondError(c, http.StatusInternalServerError, fallback)
	}
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/liveclass/handler.go"), $content_internal_liveclass_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/liveclass/handler.go" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Yellow
Write-Host "  1. go build ./... to sanity check"
Write-Host "  2. cd .. ; docker compose build --no-cache backend"
Write-Host "  3. docker compose up -d --force-recreate backend"
Write-Host "  4. docker logs ai_tutor_backend --tail 15"