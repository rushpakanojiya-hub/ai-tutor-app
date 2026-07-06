package youtube

import "time"

// YoutubeVideo is the normalized shape returned to the Flutter client.
type YoutubeVideo struct {
	VideoID     string `json:"video_id"`
	Title       string `json:"title"`
	Description string `json:"description,omitempty"`
	Thumbnail   string `json:"thumbnail"`
	ChannelName string `json:"channel"`
	PublishedAt string `json:"published_at,omitempty"`
	Duration    string `json:"duration"`
}

// Lesson is the minimal projection of the existing lessons table
// needed by this package. It intentionally does NOT redefine or
// replace the real Lesson model used elsewhere in the app.
type Lesson struct {
	ID                 int64
	Title              string
	SubjectName        string
	YoutubeSearchQuery string
	YoutubeEnabled     bool
}

// CacheEntry mirrors a row in youtube_cache.
type CacheEntry struct {
	ID           int64
	LessonID     int64
	Query        string
	ResponseJSON string
	CreatedAt    time.Time
	ExpiresAt    time.Time
}

// VideoProgress mirrors a row in lesson_video_progress.
type VideoProgress struct {
	ID             int64     `json:"id"`
	UserID         int64     `json:"user_id"`
	LessonID       int64     `json:"lesson_id"`
	VideoID        string    `json:"video_id"`
	WatchedSeconds int       `json:"watched_seconds"`
	Completed      bool      `json:"completed"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// VideoProgressRequest is the payload accepted by the progress endpoint.
type VideoProgressRequest struct {
	VideoID        string `json:"video_id" binding:"required"`
	WatchedSeconds int    `json:"watched_seconds"`
	Completed      bool   `json:"completed"`
}
