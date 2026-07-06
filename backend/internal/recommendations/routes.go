package recommendations

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches GET /api/ai/recommendations.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.GET("/ai/recommendations", authMiddleware, handler.GetRecommendations)
}
