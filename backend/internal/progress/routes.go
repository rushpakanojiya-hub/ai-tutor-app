package progress

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches /api/progress/* routes. All require auth since
// progress is always scoped to the current user.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	group := router.Group("/progress")
	group.Use(authMiddleware)
	{
		group.POST("/lessons/:id/complete", handler.MarkComplete)
		group.GET("/subjects/:id", handler.GetSubjectProgress)
	}
}
