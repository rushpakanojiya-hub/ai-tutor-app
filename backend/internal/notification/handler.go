package notification

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/pkg/logger"
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
		logger.Error("notification: List failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load notifications")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Notifications fetched", list)
}

func (h *Handler) UnreadCount(c *gin.Context) {
	userID := c.GetInt("user_id")
	count, err := h.service.CountUnread(userID)
	if err != nil {
		logger.Error("notification: UnreadCount failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to count notifications")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Count fetched", gin.H{"unread_count": count})
}

// BUG FIX: now that Repository.MarkRead reports ErrNotificationNotFound
// for a nonexistent/not-yours id (see repository.go), map it to a proper
// 404 instead of falling into the previous behavior of either a generic
// 500 or a false-positive 200.
func (h *Handler) MarkRead(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid notification id")
		return
	}
	userID := c.GetInt("user_id")
	if err := h.service.MarkRead(id, userID); err != nil {
		if errors.Is(err, ErrNotificationNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Notification not found")
			return
		}
		logger.Error("notification: MarkRead failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update notification")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Marked as read", nil)
}

func (h *Handler) MarkAllRead(c *gin.Context) {
	userID := c.GetInt("user_id")
	if err := h.service.MarkAllRead(userID); err != nil {
		logger.Error("notification: MarkAllRead failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update notifications")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "All marked as read", nil)
}
