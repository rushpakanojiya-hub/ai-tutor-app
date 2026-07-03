package users

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
	usersGroup := router.Group("/users")
	usersGroup.Use(authMiddleware)
	{
		usersGroup.PUT("/profile", h.UpdateProfile)
	}
}

func (h *Handler) UpdateProfile(c *gin.Context) {
	userID := c.GetInt("user_id")

	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Name is required")
		return
	}

	if err := h.service.UpdateProfile(userID, req); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update profile")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Profile updated", nil)
}