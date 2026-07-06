package streak

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// GetSummary handles GET /api/streak.
func (h *Handler) GetSummary(c *gin.Context) {
	userID := c.GetInt("user_id")

	summary, err := h.service.GetSummary(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load streak")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Streak fetched", summary)
}
