package subjects

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches /api/subjects/* AND /api/categories/:id/subjects
// (the latter lives here, not in the categories package, because it's
// fundamentally a subjects list — this keeps categories/routes.go from
// needing to import the subjects package).
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	subjectsGroup := router.Group("/subjects")
	subjectsGroup.Use(authMiddleware)
	{
		subjectsGroup.GET("", handler.List)
		subjectsGroup.GET("/:id", handler.GetByID)
		subjectsGroup.POST("", handler.Create)
	}

	router.GET("/categories/:id/subjects", authMiddleware, handler.ListByCategory)
}