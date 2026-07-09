package xp

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

func (h *Handler) RegisterRoutes(router *gin.RouterGroup, authMiddleware gin.HandlerFunc) {
	group := router.Group("/xp")
	group.Use(authMiddleware)
	{
		group.GET("/mine", h.GetMine)
	}
}

func (h *Handler) GetMine(c *gin.Context) {
	studentID := c.GetInt("user_id")
	summary, err := h.service.GetSummary(studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load XP")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "XP fetched", summary)
}
