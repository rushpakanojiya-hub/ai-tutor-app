// Package notification implements simple polling-based notifications -
// no WebSocket/push infra exists yet, so the app fetches these on
// refresh/open. Covers "new class"/"class cancelled" fine; a "starting
// soon" reminder needs a background scheduler that doesn't exist, so
// that trigger isn't wired up - the countdown timer in the UI covers it.
package notification

import "time"

const (
	TypeNewLiveClass       = "new_live_class"
	TypeLiveClassCancelled = "live_class_cancelled"
)

// Notification is always scoped to "my own" - UserID isn't exposed since
// every response is already filtered to the requesting user.
type Notification struct {
	ID        int       `json:"id"`
	Type      string    `json:"type"`
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	RelatedID *int      `json:"related_id"`
	IsRead    bool      `json:"is_read"`
	CreatedAt time.Time `json:"created_at"`
}
