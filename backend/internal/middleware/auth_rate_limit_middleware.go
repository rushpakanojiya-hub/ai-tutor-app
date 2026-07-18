package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// authRateLimitBucket is keyed by "IP|route" (not just IP - see the QA
// fix below - and not user_id, since login/register happen before any
// user is authenticated) - same sliding-window + periodic-sweep design
// as the AI rate limiter, so it can't leak memory the same way that one
// originally did before its own fix.
type authRateLimitBucket struct {
	mu         sync.Mutex
	timestamps map[string][]time.Time
	// maxWindow is the longest window any call site has configured so
	// far. The sweep must never purge an entry more recent than this,
	// or it would reset a still-active rate limit early (see the QA fix
	// on sweepPeriodically below). Starts at 15 minutes as a safe floor
	// and grows if a longer window is registered.
	maxWindow time.Duration
}

var authRateLimiter = newAuthRateLimitBucket()

func newAuthRateLimitBucket() *authRateLimitBucket {
	const sweepInterval = 15 * time.Minute
	b := &authRateLimitBucket{
		timestamps: make(map[string][]time.Time),
		maxWindow:  sweepInterval,
	}
	go b.sweepPeriodically(sweepInterval)
	return b
}

// QA fix ("15-min sweep purges timestamps still inside the 1-hour
// window"): this used to purge any IP whose last timestamp was older
// than the sweep's own 15-minute tick interval - but /register and
// /teacher/apply are configured for a 5-requests-per-HOUR limit. An IP
// that made a request 20 minutes ago is still well within that 1-hour
// window, yet the old code wiped its entire history at the next sweep,
// silently resetting the limit 45 minutes early. The sweep now runs on
// its own efficient interval, but only PURGES entries older than
// b.maxWindow - the longest window actually in use - so data is never
// dropped while it could still count toward an active limit.
func (b *authRateLimitBucket) sweepPeriodically(tickInterval time.Duration) {
	ticker := time.NewTicker(tickInterval)
	defer ticker.Stop()
	for range ticker.C {
		b.mu.Lock()
		cutoff := time.Now().Add(-b.maxWindow)
		for key, timestamps := range b.timestamps {
			if len(timestamps) == 0 || timestamps[len(timestamps)-1].Before(cutoff) {
				delete(b.timestamps, key)
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

		// QA fix ("All auth endpoints share one IP-keyed limiter"): the
		// key used to be the IP alone, so /login, /register, and
		// /teacher/apply - each configured with their own distinct
		// maxRequests/window - all read and wrote the SAME timestamp
		// list for a given IP. A student trying to register would burn
		// through the budget that should have been reserved for login
		// attempts (or vice versa), and the maxRequests check for
		// whichever endpoint ran would count requests made against a
		// completely different endpoint. Including the route itself in
		// the key gives each endpoint its own independent budget, as
		// the maxRequests/window pair passed in here already implies.
		key := ip + "|" + c.FullPath()

		authRateLimiter.mu.Lock()
		if window > authRateLimiter.maxWindow {
			authRateLimiter.maxWindow = window
		}
		recent := authRateLimiter.timestamps[key]

		cutoff := now.Add(-window)
		fresh := make([]time.Time, 0, len(recent))
		for _, t := range recent {
			if t.After(cutoff) {
				fresh = append(fresh, t)
			}
		}

		if len(fresh) >= maxRequests {
			if len(fresh) == 0 {
				delete(authRateLimiter.timestamps, key)
			} else {
				authRateLimiter.timestamps[key] = fresh
			}
			authRateLimiter.mu.Unlock()
			utils.RespondError(c, http.StatusTooManyRequests, "Too many attempts. Please wait a few minutes and try again.")
			c.Abort()
			return
		}

		authRateLimiter.timestamps[key] = append(fresh, now)
		authRateLimiter.mu.Unlock()

		c.Next()
	}
}
