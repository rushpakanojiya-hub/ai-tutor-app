package recommendations

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the recommendations Service.
type Handler struct {
	service *Service
}

// NewHandler builds a recommendations Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// GetRecommendations handles GET /api/ai/recommendations.
func (h *Handler) GetRecommendations(c *gin.Context) {
	userID := c.GetInt("user_id")

	list, err := h.service.GetForUser(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load recommendations")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Recommendations fetched", list)
}
