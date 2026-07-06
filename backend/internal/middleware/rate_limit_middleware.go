package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// rateLimitBucket tracks one user's recent request timestamps within the
// current window â€” a simple in-memory sliding-window limiter. Good enough
// for a single-instance MVP backend; a multi-instance deployment would
// need a shared store (e.g. Redis) instead.
type rateLimitBucket struct {
	mu        sync.Mutex
	timestamps map[int][]time.Time
}

var aiRateLimiter = &rateLimitBucket{timestamps: make(map[int][]time.Time)}

// AIRateLimitMiddleware limits each authenticated user to maxRequests
// calls per window (e.g. 10 per minute) on AI Tutor endpoints â€” these are
// the most expensive calls in the app (real LLM API cost per request),
// so they get their own stricter limit than the rest of the API.
func AIRateLimitMiddleware(maxRequests int, window time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.GetInt("user_id")
		now := time.Now()

		aiRateLimiter.mu.Lock()
		recent := aiRateLimiter.timestamps[userID]

		// Drop timestamps outside the current window.
		cutoff := now.Add(-window)
		fresh := recent[:0]
		for _, t := range recent {
			if t.After(cutoff) {
				fresh = append(fresh, t)
			}
		}

		if len(fresh) >= maxRequests {
			aiRateLimiter.timestamps[userID] = fresh
			aiRateLimiter.mu.Unlock()
			utils.RespondError(c, http.StatusTooManyRequests, "You're sending messages too quickly. Please wait a moment and try again.")
			c.Abort()
			return
		}

		aiRateLimiter.timestamps[userID] = append(fresh, now)
		aiRateLimiter.mu.Unlock()

		c.Next()
	}
}
