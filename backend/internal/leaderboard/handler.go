package leaderboard

import (
	"errors"
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

func (h *Handler) RegisterRoutes(router *gin.RouterGroup, authMiddleware gin.HandlerFunc) {
	group := router.Group("/leaderboard")
	group.Use(authMiddleware)
	{
		group.GET("", h.Get)
	}
}

// Get handles GET /api/leaderboard?period=weekly|monthly|overall&class=X&section=Y.
// A student's class/section query params are ignored server-side (see
// Service.GetLeaderboard) - they only ever get their own class either way.
func (h *Handler) Get(c *gin.Context) {
	period := c.DefaultQuery("period", PeriodOverall)
	var classFilter, sectionFilter *string
	if v := c.Query("class"); v != "" {
		classFilter = &v
	}
	if v := c.Query("section"); v != "" {
		sectionFilter = &v
	}

	userID := c.GetInt("user_id")
	role := c.GetString("role")

	entries, err := h.service.GetLeaderboard(period, classFilter, sectionFilter, userID, role)
	if err != nil {
		if errors.Is(err, ErrInvalidPeriod) {
			utils.RespondError(c, http.StatusBadRequest, "period must be weekly, monthly, or overall")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load leaderboard")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Leaderboard fetched", entries)
}
