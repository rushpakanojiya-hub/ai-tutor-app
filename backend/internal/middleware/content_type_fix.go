package middleware

import (
	"strings"

	"github.com/gin-gonic/gin"
)

// ContentTypeFix rewrites a text/plain Content-Type to application/json
// before Gin's JSON binding runs. This lets the frontend send JSON bodies
// labeled as text/plain to avoid triggering a browser CORS preflight
// (which some upstream infrastructure was blocking).
//
// BUG FIX: the previous version only matched two exact string literals
// ("text/plain" and "text/plain; charset=utf-8"). Any other equivalent
// form a client/proxy might send - different casing ("Text/Plain"), no
// space after the semicolon ("text/plain;charset=utf-8"), or a trailing
// space - fell through unrecognized, silently breaking JSON binding for
// that request. Matching is now case-insensitive and only checks the
// media type itself (ignoring any parameters).
func ContentTypeFix() gin.HandlerFunc {
	return func(c *gin.Context) {
		ct := c.GetHeader("Content-Type")
		mediaType := strings.ToLower(strings.TrimSpace(ct))
		if idx := strings.Index(mediaType, ";"); idx != -1 {
			mediaType = strings.TrimSpace(mediaType[:idx])
		}
		if mediaType == "text/plain" {
			c.Request.Header.Set("Content-Type", "application/json")
		}
		c.Next()
	}
}
