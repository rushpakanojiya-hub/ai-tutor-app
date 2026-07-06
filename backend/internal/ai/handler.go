package ai

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the ai Service.
type Handler struct {
	service *Service
}

// NewHandler builds an ai Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) respondAIError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrAINotConfigured):
		utils.RespondError(c, http.StatusServiceUnavailable, "AI Tutor is not configured yet. Please contact the app admin.")
	case errors.Is(err, ErrSessionNotFound):
		utils.RespondError(c, http.StatusNotFound, "Conversation not found")
	case errors.Is(err, ErrRateLimited):
		utils.RespondError(c, http.StatusTooManyRequests, "AI Tutor is busy right now. Please try again in a moment.")
	default:
		utils.RespondError(c, http.StatusInternalServerError, "AI Tutor is having trouble responding right now. Please try again.")
	}
}

// Chat handles POST /api/ai/chat.
func (h *Handler) Chat(c *gin.Context) {
	var req ChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A message is required")
		return
	}

	userID := c.GetInt("user_id")

	resp, err := h.service.Chat(c.Request.Context(), userID, req)
	if err != nil {
		h.respondAIError(c, err)
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Reply generated", resp)
}

// ListSessions handles GET /api/ai/sessions.
func (h *Handler) ListSessions(c *gin.Context) {
	userID := c.GetInt("user_id")

	list, err := h.service.ListSessions(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load conversations")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Sessions fetched", list)
}

// GetSession handles GET /api/ai/sessions/:id.
func (h *Handler) GetSession(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid session id")
		return
	}

	userID := c.GetInt("user_id")

	session, err := h.service.GetSession(userID, id)
	if err != nil {
		h.respondAIError(c, err)
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Session fetched", session)
}

// DeleteSession handles DELETE /api/ai/sessions/:id.
func (h *Handler) DeleteSession(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid session id")
		return
	}

	userID := c.GetInt("user_id")

	if err := h.service.DeleteSession(userID, id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to delete conversation")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Session deleted", nil)
}
