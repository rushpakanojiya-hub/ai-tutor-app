package resource

import "github.com/gin-gonic/gin"

// RegisterRoutes mounts resource endpoints onto their own /live-classes
// group (same base path as the liveclass package, but a separate Gin
// group is fine - Gin merges routes on the same prefix cleanly).
// Upload/Delete require the teacher role; List is open to any
// authenticated user (students need to see the files).
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware, requireTeacher gin.HandlerFunc) {
	group := router.Group("/live-classes")
	group.Use(authMiddleware)

	teacherGroup := group.Group("", requireTeacher)
	{
		teacherGroup.POST("/:id/resources", handler.Upload)
		teacherGroup.DELETE("/:id/resources/:resourceId", handler.Delete)
	}

	group.GET("/:id/resources", handler.List)
}
