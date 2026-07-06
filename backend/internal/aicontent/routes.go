package aicontent

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches GET /api/lessons/:id/ai-content.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.GET("/lessons/:id/ai-content", authMiddleware, handler.GetByLesson)
}
