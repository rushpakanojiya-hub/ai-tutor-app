package notification

import "github.com/gin-gonic/gin"

func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	group := router.Group("/notifications")
	group.Use(authMiddleware)
	{
		group.GET("", handler.List)
		group.GET("/unread-count", handler.UnreadCount)
		group.POST("/:id/read", handler.MarkRead)
		group.POST("/read-all", handler.MarkAllRead)
	}
}
