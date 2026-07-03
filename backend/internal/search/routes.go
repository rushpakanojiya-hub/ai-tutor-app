package search

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches GET /api/search.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.GET("/search", authMiddleware, handler.Search)
}