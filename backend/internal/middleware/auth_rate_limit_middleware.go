package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// authRateLimitBucket is keyed by client IP (not user_id, since login/
// register happen before any user is authenticated) - same sliding-
// window + periodic-sweep design as the AI rate limiter, so it can't
// leak memory the same way that one originally did before its own fix.
type authRateLimitBucket struct {
	mu         sync.Mutex
	timestamps map[string][]time.Time
}

var authRateLimiter = newAuthRateLimitBucket()

func newAuthRateLimitBucket() *authRateLimitBucket {
	b := &authRateLimitBucket{timestamps: make(map[string][]time.Time)}
	go b.sweepPeriodically(15 * time.Minute)
	return b
}

func (b *authRateLimitBucket) sweepPeriodically(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for range ticker.C {
		cutoff := time.Now().Add(-interval)
		b.mu.Lock()
		for ip, timestamps := range b.timestamps {
			if len(timestamps) == 0 || timestamps[len(timestamps)-1].Before(cutoff) {
				delete(b.timestamps, ip)
			}
		}
		b.mu.Unlock()
	}
}

// AuthRateLimitMiddleware limits each client IP to maxRequests calls per
// window on sensitive auth endpoints (login, register, teacher apply) -
// these had no rate limiting at all, making brute-force password
// guessing and registration spam trivial. Security audit fix (High:
// "Rate Limiting" on Authentication).
func AuthRateLimitMiddleware(maxRequests int, window time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()
		now := time.Now()

		authRateLimiter.mu.Lock()
		recent := authRateLimiter.timestamps[ip]

		cutoff := now.Add(-window)
		fresh := make([]time.Time, 0, len(recent))
		for _, t := range recent {
			if t.After(cutoff) {
				fresh = append(fresh, t)
			}
		}

		if len(fresh) >= maxRequests {
			if len(fresh) == 0 {
				delete(authRateLimiter.timestamps, ip)
			} else {
				authRateLimiter.timestamps[ip] = fresh
			}
			authRateLimiter.mu.Unlock()
			utils.RespondError(c, http.StatusTooManyRequests, "Too many attempts. Please wait a few minutes and try again.")
			c.Abort()
			return
		}

		authRateLimiter.timestamps[ip] = append(fresh, now)
		authRateLimiter.mu.Unlock()

		c.Next()
	}
}
