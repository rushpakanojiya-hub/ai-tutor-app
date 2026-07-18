package notes

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches /api/notes AND /api/lessons/:id/notes.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.POST("/notes", authMiddleware, handler.Create)
	router.GET("/lessons/:id/notes", authMiddleware, handler.ListByLesson)
	// Lesson Resource Management (additive)
	router.PUT("/notes/:id", authMiddleware, handler.Update)
	router.DELETE("/notes/:id", authMiddleware, handler.Delete)
}