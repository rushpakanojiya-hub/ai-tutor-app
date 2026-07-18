package streak

import (
	"net/http"
	"strconv"
	"time"

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

// --- Learning Calendar month view (additive) ---

// GetMonthCalendar handles GET /api/streak/calendar?year=2026&month=7.
// Defaults to the current year/month if not provided.
func (h *Handler) GetMonthCalendar(c *gin.Context) {
	userID := c.GetInt("user_id")
	now := time.Now()

	year, err := strconv.Atoi(c.DefaultQuery("year", strconv.Itoa(now.Year())))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid year")
		return
	}
	month, err := strconv.Atoi(c.DefaultQuery("month", strconv.Itoa(int(now.Month()))))
	if err != nil || month < 1 || month > 12 {
		utils.RespondError(c, http.StatusBadRequest, "Invalid month")
		return
	}

	calendar, err := h.service.GetMonthCalendar(userID, year, month)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load calendar")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Calendar fetched", calendar)
}