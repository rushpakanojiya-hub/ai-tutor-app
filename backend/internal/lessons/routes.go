package lessons

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches /api/lessons/* AND /api/subjects/:id/lessons
// (the latter lives here for the same reason subjects/:id/subjects lives
// in the subjects package - it's fundamentally a lessons list).
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	lessonsGroup := router.Group("/lessons")
	lessonsGroup.Use(authMiddleware)
	{
		lessonsGroup.GET("/:id", handler.GetByID)
		lessonsGroup.POST("", handler.Create)
		// Admin Course Management (additive) - all admin-gated inside
		// the handler itself.
		lessonsGroup.PUT("/:id", handler.Update)
		lessonsGroup.DELETE("/:id", handler.Delete)
		lessonsGroup.POST("/:id/upload-video", handler.UploadVideo)
		lessonsGroup.POST("/:id/upload-pdf", handler.UploadPDF)
		lessonsGroup.POST("/:id/upload-assignment", handler.UploadAssignment)
		// Lesson Resource Management (additive)
		lessonsGroup.POST("/:id/publish", handler.Publish)
		lessonsGroup.POST("/:id/unpublish", handler.Unpublish)
	}
	router.GET("/subjects/:id/lessons", authMiddleware, handler.ListBySubject)
	router.POST("/subjects/:id/lessons/reorder", authMiddleware, handler.Reorder)
}