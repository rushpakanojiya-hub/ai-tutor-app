package liveclass

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches every /api/live-classes/* route.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware, requireTeacher gin.HandlerFunc) {
	group := router.Group("/live-classes")
	group.Use(authMiddleware)

	teacherGroup := group.Group("", requireTeacher)
	{
		teacherGroup.POST("", handler.Create)
		teacherGroup.PUT("/:id", handler.Update)
		teacherGroup.DELETE("/:id", handler.Delete)
		teacherGroup.POST("/:id/cancel", handler.Cancel)
		teacherGroup.POST("/:id/complete", handler.MarkCompleted)
		teacherGroup.GET("/mine", handler.ListMine)
		teacherGroup.GET("/:id/attendance", handler.ListAttendance)
		teacherGroup.POST("/:id/start", handler.Start)
		teacherGroup.POST("/:id/end", handler.End)
	}

	group.GET("/:id", handler.GetByID)
	group.GET("/for-student", handler.ListForStudent)
	group.GET("/attendance-summary", handler.AttendanceSummary)
	group.POST("/:id/check-in", handler.CheckIn)
	group.GET("/:id/my-attendance", handler.GetMyAttendance)
	group.POST("/:id/join", handler.Join)
	group.GET("/:id/meeting-status", handler.MeetingStatus)
}

// RegisterAdminRoutes attaches the admin-only monitoring endpoints.
func RegisterAdminRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware, requireAdmin gin.HandlerFunc) {
	router.GET("/admin/live-classes", authMiddleware, requireAdmin, handler.ListAllForAdmin)
	router.POST("/admin/live-classes/:id/cancel", authMiddleware, requireAdmin, handler.AdminCancel)
}
