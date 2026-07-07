package notification

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

func (h *Handler) List(c *gin.Context) {
	userID := c.GetInt("user_id")
	list, err := h.service.ListForUser(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load notifications")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Notifications fetched", list)
}

func (h *Handler) UnreadCount(c *gin.Context) {
	userID := c.GetInt("user_id")
	count, err := h.service.CountUnread(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to count notifications")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Count fetched", gin.H{"unread_count": count})
}

func (h *Handler) MarkRead(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid notification id")
		return
	}
	userID := c.GetInt("user_id")
	if err := h.service.MarkRead(id, userID); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update notification")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Marked as read", nil)
}

func (h *Handler) MarkAllRead(c *gin.Context) {
	userID := c.GetInt("user_id")
	if err := h.service.MarkAllRead(userID); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update notifications")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "All marked as read", nil)
}
