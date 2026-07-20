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