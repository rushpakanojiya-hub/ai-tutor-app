package streak

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches GET /api/streak.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.GET("/streak", authMiddleware, handler.GetSummary)
	// Learning Calendar month view (additive)
	router.GET("/streak/calendar", authMiddleware, handler.GetMonthCalendar)
}