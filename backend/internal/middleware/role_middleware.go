package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/internal/constants"
	"ai-tutor-backend/utils"
)

func RequireRole(allowedRoles ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists {
			utils.RespondError(c, http.StatusUnauthorized, "Authentication required")
			c.Abort()
			return
		}

		roleStr, _ := role.(string)
		for _, allowed := range allowedRoles {
			if roleStr == allowed {
				c.Next()
				return
			}
		}

		utils.RespondError(c, http.StatusForbidden, "You do not have permission to access this resource")
		c.Abort()
	}
}

func RequireStudent() gin.HandlerFunc { return RequireRole(constants.RoleStudent) }
func RequireTeacher() gin.HandlerFunc { return RequireRole(constants.RoleTeacher) }
func RequireParent() gin.HandlerFunc  { return RequireRole(constants.RoleParent) }
func RequireAdmin() gin.HandlerFunc   { return RequireRole(constants.RoleAdmin) }