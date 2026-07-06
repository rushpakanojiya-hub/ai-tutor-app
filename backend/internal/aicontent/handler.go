package aicontent

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the aicontent Service.
type Handler struct {
	service *Service
}

// NewHandler builds an aicontent Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// GetByLesson handles GET /api/lessons/:id/ai-content.
func (h *Handler) GetByLesson(c *gin.Context) {
	lessonID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}

	content, err := h.service.GetByLesson(lessonID)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			// Not an error state for the client â€” just means this lesson
			// doesn't have AI content generated yet. 404 lets the Flutter
			// side distinguish "none yet" from a real server failure.
			utils.RespondError(c, http.StatusNotFound, "AI content not available for this lesson yet")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load AI content")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "AI content fetched", content)
}
