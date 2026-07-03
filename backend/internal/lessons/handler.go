package lessons

import (
	"errors"
	"net/http"
	"strconv"

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

// Create handles POST /api/lessons.
// NOTE: not role-gated yet — see the same comment in categories/handler.go.
func (h *Handler) Create(c *gin.Context) {
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