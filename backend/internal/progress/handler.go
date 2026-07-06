package progress

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the progress Service.
type Handler struct {
	service *Service
}

// NewHandler builds a progress Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// markCompleteRequest is optional â€” the request body can be empty (old
// behavior) or include a quiz score. Both work.
type markCompleteRequest struct {
	Score *int `json:"score"`
}

// MarkComplete handles POST /api/progress/lessons/:id/complete.
// The user is identified from the JWT (set by AuthMiddleware), not from
// the request body â€” a user can only mark their own progress.
func (h *Handler) MarkComplete(c *gin.Context) {
	lessonID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}

	var req markCompleteRequest
	// Body is optional â€” ignore bind errors from an empty body.
	_ = c.ShouldBindJSON(&req)

	userID := c.GetInt("user_id")

	if err := h.service.MarkLessonComplete(userID, lessonID, req.Score); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to save progress")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Lesson marked complete", nil)
}

// GetSubjectProgress handles GET /api/progress/subjects/:id.
func (h *Handler) GetSubjectProgress(c *gin.Context) {
	subjectID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid subject id")
		return
	}

	userID := c.GetInt("user_id")

	result, err := h.service.SubjectProgress(userID, subjectID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load progress")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Progress fetched", result)
}
