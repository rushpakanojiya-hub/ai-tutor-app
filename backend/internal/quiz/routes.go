package quiz

import (
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/internal/middleware"
)

// RegisterRoutes attaches all /api/quiz/* routes. Generation is
// additionally rate-limited since each call has a real Groq API cost.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	group := router.Group("/quiz")
	group.Use(authMiddleware)

	genRateLimit := middleware.AIRateLimitMiddleware(15, time.Minute)

	{
		group.POST("/lessons/:id/attempt", handler.SubmitLessonAttempt)
		group.POST("/freeform/attempt", handler.SubmitFreeformAttempt)
		group.GET("/attempts", handler.ListAttempts)
		group.GET("/attempts/:id", handler.GetAttempt)
		group.GET("/analytics", handler.GetAnalytics)
		group.POST("/generate", genRateLimit, handler.GenerateQuiz)
	}
}
