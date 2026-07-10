package categories

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches all /api/categories/* routes. All routes require
// auth; admin-only ones are gated inside the handler. authMiddleware is
// passed in from main.go instead of imported here, so this package
// doesn't need to know about internal/middleware.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	group := router.Group("/categories")
	group.Use(authMiddleware)
	{
		group.GET("", handler.List)
		group.GET("/:id", handler.GetByID)
		group.POST("", handler.Create)
		// Course Categories management (additive) - admin-gated inside
		// the handler itself.
		group.PUT("/:id", handler.Update)
	}
}
