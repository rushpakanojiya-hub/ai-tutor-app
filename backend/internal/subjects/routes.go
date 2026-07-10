package subjects

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches /api/subjects/* AND /api/categories/:id/subjects
// (the latter lives here, not in the categories package, because it's
// fundamentally a subjects list - this keeps categories/routes.go from
// needing to import the subjects package).
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	subjectsGroup := router.Group("/subjects")
	subjectsGroup.Use(authMiddleware)
	{
		subjectsGroup.GET("", handler.List)
		subjectsGroup.GET("/:id", handler.GetByID)
		subjectsGroup.POST("", handler.Create)
		// Admin Course Management (additive) - Update/Delete/Publish/
		// Unpublish are all admin-gated inside the handler itself.
		subjectsGroup.PUT("/:id", handler.Update)
		subjectsGroup.DELETE("/:id", handler.Delete)
		subjectsGroup.POST("/:id/publish", handler.Publish)
		subjectsGroup.POST("/:id/unpublish", handler.Unpublish)
	}
	router.GET("/categories/:id/subjects", authMiddleware, handler.ListByCategory)
	// Admin Course Management list (search/filter/status) - lives under
	// /admin, same convention as /admin/students, /admin/dashboard, etc.
	router.GET("/admin/courses", authMiddleware, handler.AdminList)
}
