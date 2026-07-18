package middleware

import "github.com/gin-gonic/gin"

// ContentTypeFix rewrites a text/plain Content-Type to application/json
// before Gin's JSON binding runs. This lets the frontend send JSON bodies
// labeled as text/plain to avoid triggering a browser CORS preflight
// (which some upstream infrastructure was blocking).
func ContentTypeFix() gin.HandlerFunc {
	return func(c *gin.Context) {
		ct := c.GetHeader("Content-Type")
		if ct == "text/plain" || ct == "text/plain; charset=utf-8" {
			c.Request.Header.Set("Content-Type", "application/json")
		}
		c.Next()
	}
}