package middleware

import (
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// CORSMiddleware restricts cross-origin requests to an explicit allow-
// list instead of a wildcard.
//
// Security audit fix (High: "CORS"): this previously allowed every
// origin ("*"), which - combined with any future browser-based client
// (a web admin panel, Flutter Web, etc.) - would let any website make
// requests against this API on a logged-in user's behalf. The native
// mobile app is unaffected either way, since CORS is a browser-enforced
// mechanism that mobile HTTP clients never trigger.
func CORSMiddleware(allowedOrigins []string) gin.HandlerFunc {
	return cors.New(cors.Config{
		AllowOrigins:     allowedOrigins,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: false,
		MaxAge:           12 * time.Hour,
	})
}
