package assignment

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches every /api/assignments/* route. requireTeacher
// gates teacher-authoring endpoints; the plain authMiddleware group covers
// student-facing read/submit endpoints (any signed-in student can view
// and submit - there's no per-student enrollment restriction anywhere in
// this app yet, matching how lessons/quizzes already work).
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware, requireTeacher gin.HandlerFunc) {
	group := router.Group("/assignments")
	group.Use(authMiddleware)

	// Teacher-only authoring endpoints.
	teacherGroup := group.Group("", requireTeacher)
	{
		teacherGroup.POST("", handler.Create)
		teacherGroup.PUT("/:id", handler.Update)
		teacherGroup.DELETE("/:id", handler.Delete)
		teacherGroup.POST("/:id/publish", handler.Publish)
		teacherGroup.POST("/:id/unpublish", handler.Unpublish)
		teacherGroup.POST("/:id/close", handler.Close)
		teacherGroup.POST("/:id/archive", handler.Archive)
		teacherGroup.POST("/generate-ai", handler.GenerateAI)
		teacherGroup.GET("/mine", handler.ListMine)
		teacherGroup.GET("/analytics", handler.TeacherAnalytics)
		teacherGroup.GET("/:id/submissions", handler.ListSubmissions)
		teacherGroup.POST("/submissions/:id/review", handler.ReviewSubmission)
	}

	// Any signed-in user can view an assignment's detail and submit to it.
	group.GET("/:id", handler.GetByID)
	group.POST("/:id/draft", handler.SaveDraft)
	group.POST("/:id/submit", handler.Submit)
	group.GET("/:id/my-submission", handler.GetMySubmission)
	group.POST("/submissions/:id/retry-evaluation", handler.RetryEvaluation)
}

// RegisterSubjectRoute attaches GET /api/subjects/:id/assignments onto the
// existing subjects route group (called separately since it's nested
// under a different path prefix than the rest of this package).
func RegisterSubjectRoute(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.GET("/subjects/:id/assignments", authMiddleware, handler.ListForSubject)
}

// RegisterAdminRoutes attaches the admin-only monitoring endpoints.
func RegisterAdminRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware, requireAdmin gin.HandlerFunc) {
	adminGroup := router.Group("/admin/assignments")
	adminGroup.Use(authMiddleware, requireAdmin)
	{
		adminGroup.GET("", handler.ListAllForAdmin)
		adminGroup.GET("/analytics", handler.AdminAnalytics)
	}
}
