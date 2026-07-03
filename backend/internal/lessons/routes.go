package lessons

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches /api/lessons/* AND /api/subjects/:id/lessons
// (the latter lives here for the same reason subjects/:id/subjects lives
// in the subjects package — it's fundamentally a lessons list).
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	lessonsGroup := router.Group("/lessons")
	lessonsGroup.Use(authMiddleware)
	{
		lessonsGroup.GET("/:id", handler.GetByID)
		lessonsGroup.POST("", handler.Create)
	}

	router.GET("/subjects/:id/lessons", authMiddleware, handler.ListBySubject)
}