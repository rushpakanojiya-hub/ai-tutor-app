package notes

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

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

// ListByLesson handles GET /api/lessons/:id/notes.
func (h *Handler) ListByLesson(c *gin.Context) {
	lessonID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}

	list, err := h.service.ListByLesson(lessonID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load notes")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Notes fetched", list)
}

// Create handles POST /api/notes.
// NOTE: not role-gated yet — see the same comment in categories/handler.go.
func (h *Handler) Create(c *gin.Context) {
	var req CreateNoteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "lesson_id, title, and pdf_url are required")
		return
	}

	id, err := h.service.Create(req)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Note created", gin.H{"id": id})
}