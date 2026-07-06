package streak

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches GET /api/streak.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.GET("/streak", authMiddleware, handler.GetSummary)
}
