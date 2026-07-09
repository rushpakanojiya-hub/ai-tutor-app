package badge

import (
	"net/http"
	"strconv"

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
	group := router.Group("/badges")
	group.Use(authMiddleware)
	{
		group.GET("/mine", h.ListMine)
		group.GET("/student/:id", h.ListForStudent)
	}
}

// ListMine handles GET /api/badges/mine - the student's own badge page.
func (h *Handler) ListMine(c *gin.Context) {
	studentID := c.GetInt("user_id")
	badges, err := h.service.ListForStudent(studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load badges")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Badges fetched", badges)
}

// ListForStudent handles GET /api/badges/student/:id - teacher/admin
// viewing a specific student's badges (view-only, they can't earn badges
// themselves).
func (h *Handler) ListForStudent(c *gin.Context) {
	role := c.GetString("role")
	if role != "teacher" && role != "admin" {
		utils.RespondError(c, http.StatusForbidden, "Only teachers and admins can view another student's badges")
		return
	}

	studentID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid student id")
		return
	}

	badges, err := h.service.ListForStudent(studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load badges")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Badges fetched", badges)
}
