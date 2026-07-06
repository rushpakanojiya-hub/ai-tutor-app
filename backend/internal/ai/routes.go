package ai

import (
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/internal/middleware"
)

// RegisterRoutes attaches all /api/ai/* chat routes. All require auth
// since chat history is scoped to the current user. Chat itself (the
// route that calls the real Groq API) is additionally rate-limited per
// user since each call has a real API cost and Groq's own limits apply.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	group := router.Group("/ai")
	group.Use(authMiddleware)

	aiRateLimit := middleware.AIRateLimitMiddleware(15, time.Minute)

	{
		group.POST("/chat", aiRateLimit, handler.Chat)
		group.GET("/sessions", handler.ListSessions)
		group.GET("/sessions/:id", handler.GetSession)
		group.DELETE("/sessions/:id", handler.DeleteSession)
	}
}
