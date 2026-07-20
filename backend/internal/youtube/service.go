package youtube

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"strings"
)

// ErrLessonNotFound is returned when the requested lesson doesn't exist,
// so the handler can map it to 404 instead of a generic 500.
var ErrLessonNotFound = errors.New("lesson not found")

// ErrEmptyQuery is returned when a search query is empty after trimming.
var ErrEmptyQuery = errors.New("search query must not be empty")

const maxSearchQueryLen = 200

// Service orchestrates: read lesson -> resolve query -> check cache ->
// call YouTube API -> cache -> return.
type Service struct {
	repo   *Repository
	client *Client
}

func NewService(repo *Repository, client *Client) *Service {
	return &Service{repo: repo, client: client}
}

// GetVideosForLesson returns educational videos for a lesson, using the
// 24h cache when available.
func (s *Service) GetVideosForLesson(ctx context.Context, lessonID int64) ([]YoutubeVideo, error) {
	lesson, err := s.repo.GetLesson(ctx, lessonID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrLessonNotFound
		}
		return nil, err
	}

	if !lesson.YoutubeEnabled {
		return []YoutubeVideo{}, nil
	}

	query := lesson.YoutubeSearchQuery
	if query == "" {
		query = GenerateSearchQuery(lesson.Title, lesson.SubjectName)
		if err := s.repo.SaveGeneratedQuery(ctx, lesson.ID, query); err != nil {
			// Non-fatal: we can still serve this request even if persisting fails.
			log.Printf("youtube: failed to persist generated query for lesson %d: %v", lessonID, err)
		}
	}

	if cached, ok, err := s.repo.GetCachedVideos(ctx, lessonID, query); err == nil && ok {
		return cached, nil
	} else if err != nil {
		log.Printf("youtube: cache read failed (continuing to live fetch): %v", err)
	}

	videos, err := s.client.Search(ctx, query)
	if err != nil {
		// Fallback: try one alternate phrasing before giving up.
		variants := GenerateQueryVariants(lesson.Title, lesson.SubjectName)
		for _, alt := range variants {
			if v2, err2 := s.client.Search(ctx, alt); err2 == nil && len(v2) > 0 {
				videos, err = v2, nil
				break
			}
		}
		if err != nil {
			return nil, err
		}
	}

	if len(videos) == 0 {
		videos = []YoutubeVideo{}
	}

	if err := s.repo.SaveCache(ctx, lessonID, query, videos); err != nil {
		log.Printf("youtube: failed to write cache for lesson %d: %v", lessonID, err)
	}

	return videos, nil
}

// SearchVideos powers the generic GET /api/videos/search?q= endpoint.
// The query is trimmed and length-capped before it's ever sent to the
// YouTube API - both to avoid wasted quota on garbage input and to keep
// an abusive/oversized query out of upstream request logs.
func (s *Service) SearchVideos(ctx context.Context, q string) ([]YoutubeVideo, error) {
	q = strings.TrimSpace(q)
	if q == "" {
		return nil, ErrEmptyQuery
	}
	if len(q) > maxSearchQueryLen {
		q = q[:maxSearchQueryLen]
	}
	return s.client.Search(ctx, q)
}

// RecordProgress saves a user's watch progress for a video within a lesson.
func (s *Service) RecordProgress(ctx context.Context, userID, lessonID int64, req VideoProgressRequest) error {
	if strings.TrimSpace(req.VideoID) == "" {
		return errors.New("video_id is required")
	}
	if req.WatchedSeconds < 0 {
		return errors.New("watched_seconds must not be negative")
	}
	return s.repo.UpsertProgress(ctx, userID, lessonID, req)
}
