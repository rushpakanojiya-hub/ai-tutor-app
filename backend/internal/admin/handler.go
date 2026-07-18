package admin

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

// GetDashboard handles GET /api/admin/dashboard.
func (h *Handler) GetDashboard(c *gin.Context) {
	stats, err := h.service.GetDashboardStats()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load dashboard stats")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Dashboard stats fetched", stats)
}

// --- Student Progress Overview (additive) ---

// GetStudentProgress handles GET /api/admin/students/progress.
func (h *Handler) GetStudentProgress(c *gin.Context) {
	list, err := h.service.ListStudentProgress()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load student progress")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Student progress fetched", list)
}