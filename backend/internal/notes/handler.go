package notes

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/pkg/logger"
	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the notes Service.
type Handler struct {
	service *Service
}

// NewHandler builds a notes Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// requireTeacherOrAdmin mirrors lessons.requireTeacherOrAdmin - PDF
// notes are managed from inside the Lesson page by the same roles that
// manage the lesson itself.
func requireTeacherOrAdmin(c *gin.Context) bool {
	role := c.GetString("role")
	if role != "admin" && role != "teacher" {
		utils.RespondError(c, http.StatusForbidden, "Only teachers and admins can manage notes")
		return false
	}
	return true
}

// isValidationError reports whether err is one of the plain input-
// validation errors Service.Create returns directly - these only ever
// describe the client's own input and are safe to show verbatim.
// Anything else (e.g. a foreign-key violation because lesson_id doesn't
// exist) is a real DB error and must not be echoed to the client.
func isValidationError(err error) bool {
	switch err.Error() {
	case "title and pdf_url are required", "a valid lesson_id is required":
		return true
	default:
		return false
	}
}

// ListByLesson handles GET /api/lessons/:id/notes.
func (h *Handler) ListByLesson(c *gin.Context) {
	lessonID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	list, err := h.service.ListByLesson(lessonID)
	if err != nil {
		logger.Error("notes: ListByLesson failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load notes")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Notes fetched", list)
}

// Create handles POST /api/notes (teacher or admin).
//
// QA fix: previously had no role check - any authenticated user could
// create a note.
//
// BUG FIX (info leak): a DB error (e.g. lesson_id referencing a lesson
// that doesn't exist -> foreign-key violation) used to be sent to the
// client verbatim via err.Error(). Only known-safe validation messages
// are shown now; anything else is logged server-side.
func (h *Handler) Create(c *gin.Context) {
	if !requireTeacherOrAdmin(c) {
		return
	}
	var req CreateNoteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "lesson_id, title, and pdf_url are required")
		return
	}
	id, err := h.service.Create(req)
	if err != nil {
		if isValidationError(err) {
			utils.RespondError(c, http.StatusBadRequest, err.Error())
			return
		}
		logger.Error("notes: Create failed", err)
		utils.RespondError(c, http.StatusBadRequest, "Could not create note - check that the lesson exists")
		return
	}
	utils.RespondSuccess(c, http.StatusCreated, "Note created", gin.H{"id": id})
}

// --- Lesson Resource Management (additive) ---

// Update handles PUT /api/notes/:id (teacher or admin) - "Replace PDF"
// and editing PDF title/description.
//
// BUG FIX (info leak): same reasoning as Create above.
func (h *Handler) Update(c *gin.Context) {
	if !requireTeacherOrAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid note id")
		return
	}
	var req UpdateNoteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	if err := h.service.Update(id, req); err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Note not found")
			return
		}
		logger.Error("notes: Update failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update note")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Note updated", nil)
}

// Delete handles DELETE /api/notes/:id (teacher or admin) - "Remove PDF".
func (h *Handler) Delete(c *gin.Context) {
	if !requireTeacherOrAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid note id")
		return
	}
	if err := h.service.Delete(id); err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Note not found")
			return
		}
		logger.Error("notes: Delete failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to delete note")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Note deleted", nil)
}
