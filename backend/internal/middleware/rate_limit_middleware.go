package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// rateLimitBucket tracks one user's recent request timestamps within the
// current window - a simple in-memory sliding-window limiter. Good enough
// for a single-instance MVP backend; a multi-instance deployment would
// need a shared store (e.g. Redis) instead.
//
// QA fix ("Rate limiter memory leak"): the timestamps map used to only
// ever grow - once a user_id was added, its entry (even once emptied by
// window-expiry) stayed in the map forever, for the lifetime of the
// process. Now: (1) an emptied entry is deleted immediately rather than
// left behind as an empty slice, and (2) a background sweep periodically
// purges any entries whose newest timestamp has aged out, catching users
// who never make another request to trigger their own cleanup.
type rateLimitBucket struct {
	mu         sync.Mutex
	timestamps map[int][]time.Time
}

var aiRateLimiter = newRateLimitBucket()

func newRateLimitBucket() *rateLimitBucket {
	b := &rateLimitBucket{timestamps: make(map[int][]time.Time)}
	go b.sweepPeriodically(5 * time.Minute)
	return b
}

// sweepPeriodically removes any user's entry whose most recent timestamp
// is older than the sweep interval - a generous bound, since any
// realistic rate-limit window (seconds to a few minutes) is far shorter
// than this, so it never interferes with active limiting.
func (b *rateLimitBucket) sweepPeriodically(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for range ticker.C {
		cutoff := time.Now().Add(-interval)
		b.mu.Lock()
		for userID, timestamps := range b.timestamps {
			if len(timestamps) == 0 || timestamps[len(timestamps)-1].Before(cutoff) {
				delete(b.timestamps, userID)
			}
		}
		b.mu.Unlock()
	}
}

// AIRateLimitMiddleware limits each authenticated user to maxRequests
// calls per window (e.g. 10 per minute) on AI Tutor endpoints - these are
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
		fresh := make([]time.Time, 0, len(recent))
		for _, t := range recent {
			if t.After(cutoff) {
				fresh = append(fresh, t)
			}
		}

		if len(fresh) >= maxRequests {
			if len(fresh) == 0 {
				delete(aiRateLimiter.timestamps, userID)
			} else {
				aiRateLimiter.timestamps[userID] = fresh
			}
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
