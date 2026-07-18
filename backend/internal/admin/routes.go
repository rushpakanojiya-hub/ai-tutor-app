package admin

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches GET /api/admin/dashboard - guarded by
// authMiddleware + requireAdmin (passed in from main.go, same
// middleware.RequireAdmin() used by the teacher-approval endpoints).
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware, requireAdmin gin.HandlerFunc) {
	group := router.Group("/admin")
	group.Use(authMiddleware, requireAdmin)
	{
		group.GET("/dashboard", handler.GetDashboard)
		// Student Progress Overview (additive)
		group.GET("/students/progress", handler.GetStudentProgress)
	}
}