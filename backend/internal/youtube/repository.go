package youtube

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"
)

// Repository handles all DB access for the youtube package. It only reads
// the minimal fields it needs from lessons/subjects and never mutates
// anything outside youtube_search_query, youtube_cache, and
// lesson_video_progress.
type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// GetLesson fetches the minimal lesson projection needed for video search.
// Returns sql.ErrNoRows (unwrapped, checked with errors.Is upstream) if the
// lesson doesn't exist, so callers can distinguish "not found" from a real
// DB failure.
func (r *Repository) GetLesson(ctx context.Context, lessonID int64) (*Lesson, error) {
	const q = `
		SELECT l.id, l.title, COALESCE(s.name, ''), COALESCE(l.youtube_search_query, ''), COALESCE(l.youtube_enabled, true)
		FROM lessons l
		LEFT JOIN subjects s ON s.id = l.subject_id
		WHERE l.id = $1`

	var lesson Lesson
	err := r.db.QueryRowContext(ctx, q, lessonID).Scan(
		&lesson.ID, &lesson.Title, &lesson.SubjectName,
		&lesson.YoutubeSearchQuery, &lesson.YoutubeEnabled,
	)
	if err != nil {
		return nil, err
	}
	return &lesson, nil
}

// SaveGeneratedQuery persists an auto-generated search query back onto the
// lesson row so future requests don't need to regenerate it.
func (r *Repository) SaveGeneratedQuery(ctx context.Context, lessonID int64, query string) error {
	const q = `UPDATE lessons SET youtube_search_query = $1 WHERE id = $2`
	res, err := r.db.ExecContext(ctx, q, query, lessonID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("youtube: no lesson row updated for id %d (lesson may have been deleted)", lessonID)
	}
	return nil
}

// GetCachedVideos returns a non-expired cache entry for lessonID+query, if any.
// expires_at/created_at are TIMESTAMPTZ columns, so comparing against
// Postgres's now() is already timezone-safe (both are stored/compared as
// UTC instants regardless of session timezone) - no explicit conversion needed.
func (r *Repository) GetCachedVideos(ctx context.Context, lessonID int64, query string) ([]YoutubeVideo, bool, error) {
	const q = `
		SELECT response_json FROM youtube_cache
		WHERE lesson_id = $1 AND query = $2 AND expires_at > now()
		ORDER BY created_at DESC LIMIT 1`

	var raw []byte
	err := r.db.QueryRowContext(ctx, q, lessonID, query).Scan(&raw)
	if err == sql.ErrNoRows {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}

	var videos []YoutubeVideo
	if err := json.Unmarshal(raw, &videos); err != nil {
		return nil, false, err
	}
	return videos, true, nil
}

// SaveCache stores fresh results with a 24h TTL. Timestamps are computed in
// UTC in application code (rather than relying on the DB's now()/session
// timezone) so cache expiry stays consistent regardless of the Postgres
// server's configured timezone.
func (r *Repository) SaveCache(ctx context.Context, lessonID int64, query string, videos []YoutubeVideo) error {
	raw, err := json.Marshal(videos)
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	const q = `
		INSERT INTO youtube_cache (lesson_id, query, response_json, created_at, expires_at)
		VALUES ($1, $2, $3, $4, $5)`
	_, err = r.db.ExecContext(ctx, q, lessonID, query, raw, now, now.Add(24*time.Hour))
	return err
}

// UpsertProgress records/updates how much of a video a user has watched.
func (r *Repository) UpsertProgress(ctx context.Context, userID, lessonID int64, req VideoProgressRequest) error {
	const q = `
		INSERT INTO lesson_video_progress (user_id, lesson_id, video_id, watched_seconds, completed, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (user_id, lesson_id, video_id)
		DO UPDATE SET watched_seconds = EXCLUDED.watched_seconds,
		              completed = EXCLUDED.completed,
		              updated_at = EXCLUDED.updated_at`
	res, err := r.db.ExecContext(ctx, q, userID, lessonID, req.VideoID, req.WatchedSeconds, req.Completed, time.Now().UTC())
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("youtube: progress upsert affected 0 rows for user %d, lesson %d", userID, lessonID)
	}
	return nil
}
