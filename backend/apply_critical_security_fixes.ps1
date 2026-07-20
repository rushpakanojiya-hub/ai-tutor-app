# apply_critical_security_fixes.ps1
# Run from your backend project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\backend)
# Writes: youtube module (API key leak fix) + quiz module (answer-tampering fix) + new migration.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying critical security fixes in $root" -ForegroundColor Cyan

# --- internal/youtube/youtube_client.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/youtube") | Out-Null
$content_internal_youtube_youtube_client_go = @'
package youtube

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"
)

const youtubeSearchEndpoint = "https://www.googleapis.com/youtube/v3/search"
const youtubeVideosEndpoint = "https://www.googleapis.com/youtube/v3/videos"

// PriorityChannels are boosted in ranking. Matching is by channel title substring.
var PriorityChannels = []string{
	"Khan Academy",
	"Crash Course",
	"TED-Ed",
	"National Geographic",
	"BBC Learning",
	"MIT OpenCourseWare",
	"Coursera",
	"freeCodeCamp",
	"Google Developers",
	"Flutter",
}

// blockedKeywords filters out non-educational content by title/description heuristics.
var blockedKeywords = []string{
	"#shorts", "shorts", "official music video", "official video", "lyrics",
	"gameplay", "let's play", "reaction", "prank", "vlog", "meme",
}

// apiKeyParamPattern matches the "key=<value>" query parameter so it can be
// redacted from any string (error message or log line) before it is ever
// written out. This is the fix for the CRITICAL API-key leak: Go's
// *url.Error stringifies the full request URL - including "?...&key=SECRET"
// - inside err.Error(). Every error that might carry a request URL is
// passed through redact() before leaving this file.
var apiKeyParamPattern = regexp.MustCompile(`(?i)([?&]key=)[^&\s"']+`)

func redact(s string) string {
	return apiKeyParamPattern.ReplaceAllString(s, "${1}REDACTED")
}

// Client is a dedicated, self-contained YouTube Data API v3 client with
// timeout, retry, multi-key rotation on quota/rate-limit errors, and logging.
//
// Multiple keys let you spread requests across several YouTube Data API
// quotas (each Google Cloud project gets its own 10,000 units/day by
// default) instead of hitting one project's ceiling.
type Client struct {
	apiKeys    []string
	maxResults int
	httpClient *http.Client

	mu           sync.Mutex
	currentIdx   int
	blockedUntil map[int]time.Time // key index -> cooldown expiry
}

// NewClient builds a YouTube client from one or more API keys.
// maxResults comes from YOUTUBE_MAX_RESULTS.
func NewClient(apiKeys []string, maxResults int) *Client {
	if maxResults <= 0 {
		maxResults = 5
	}
	clean := make([]string, 0, len(apiKeys))
	for _, k := range apiKeys {
		k = strings.TrimSpace(k)
		if k != "" {
			clean = append(clean, k)
		}
	}
	return &Client{
		apiKeys:      clean,
		maxResults:   maxResults,
		httpClient:   &http.Client{Timeout: 8 * time.Second},
		blockedUntil: make(map[int]time.Time),
	}
}

type searchResponse struct {
	Items []struct {
		ID struct {
			VideoID string `json:"videoId"`
		} `json:"id"`
		Snippet struct {
			Title        string `json:"title"`
			Description  string `json:"description"`
			ChannelTitle string `json:"channelTitle"`
			PublishedAt  string `json:"publishedAt"`
			Thumbnails   struct {
				High struct {
					URL string `json:"url"`
				} `json:"high"`
				Medium struct {
					URL string `json:"url"`
				} `json:"medium"`
			} `json:"thumbnails"`
		} `json:"snippet"`
	} `json:"items"`
}

type videosResponse struct {
	Items []struct {
		ID             string `json:"id"`
		ContentDetails struct {
			Duration string `json:"duration"`
		} `json:"contentDetails"`
	} `json:"items"`
}

// Search queries YouTube for educational videos matching q, rotating across
// configured API keys if one hits its quota, applies channel priority
// ranking and blocklist filtering, and enriches results with duration.
//
// Every error returned by this function is guaranteed redact()-safe - it
// will never contain any configured API key, even if the underlying HTTP
// client error (e.g. a *url.Error from a dial/timeout failure) embedded
// the full request URL.
func (c *Client) Search(ctx context.Context, q string) ([]YoutubeVideo, error) {
	if len(c.apiKeys) == 0 {
		return nil, fmt.Errorf("youtube: no YOUTUBE_API_KEY configured")
	}

	var sr searchResponse
	var lastErr error
	attempted := 0

	for attempted < len(c.apiKeys) {
		idx, key, ok := c.nextAvailableKey()
		if !ok {
			break // all keys currently in cooldown
		}
		attempted++

		params := url.Values{}
		params.Set("part", "snippet")
		params.Set("q", q)
		params.Set("type", "video")
		params.Set("videoDuration", "medium") // excludes most Shorts
		params.Set("safeSearch", "strict")
		params.Set("relevanceLanguage", "en")
		params.Set("maxResults", fmt.Sprintf("%d", c.maxResults*2)) // over-fetch, then filter/rank
		params.Set("key", key)

		err := c.getWithRetry(ctx, youtubeSearchEndpoint+"?"+params.Encode(), &sr)
		if err == nil {
			break
		}

		lastErr = err
		if isQuotaError(err) {
			log.Printf("youtube: key #%d exhausted/rate-limited, rotating to next key", idx)
			c.markBlocked(idx)
			continue
		}
		// Non-quota error (network, 5xx, etc.) - don't burn through all keys, just fail.
		return nil, err
	}

	if attempted == 0 {
		return nil, fmt.Errorf("youtube: all configured API keys are currently in cooldown")
	}

	if lastErr != nil && len(sr.Items) == 0 {
		return nil, fmt.Errorf("youtube: all configured keys exhausted or failed")
	}

	if len(sr.Items) == 0 {
		return []YoutubeVideo{}, nil
	}

	videoIDs := make([]string, 0, len(sr.Items))
	byID := map[string]YoutubeVideo{}
	for _, item := range sr.Items {
		v := YoutubeVideo{
			VideoID:     item.ID.VideoID,
			Title:       item.Snippet.Title,
			Description: item.Snippet.Description,
			ChannelName: item.Snippet.ChannelTitle,
			PublishedAt: item.Snippet.PublishedAt,
		}
		if item.Snippet.Thumbnails.High.URL != "" {
			v.Thumbnail = item.Snippet.Thumbnails.High.URL
		} else {
			v.Thumbnail = item.Snippet.Thumbnails.Medium.URL
		}
		if v.VideoID == "" || isBlocked(v.Title, v.Description) {
			continue
		}
		videoIDs = append(videoIDs, v.VideoID)
		byID[v.VideoID] = v
	}

	if len(videoIDs) == 0 {
		return []YoutubeVideo{}, nil
	}

	// Enrich with duration via videos.list (batched, 1 call), using
	// whichever key currently works.
	if _, key, ok := c.nextAvailableKey(); ok {
		durParams := url.Values{}
		durParams.Set("part", "contentDetails")
		durParams.Set("id", strings.Join(videoIDs, ","))
		durParams.Set("key", key)

		var vr videosResponse
		if err := c.getWithRetry(ctx, youtubeVideosEndpoint+"?"+durParams.Encode(), &vr); err == nil {
			for _, item := range vr.Items {
				if v, ok := byID[item.ID]; ok {
					v.Duration = formatISO8601Duration(item.ContentDetails.Duration)
					byID[item.ID] = v
				}
			}
		} else {
			log.Printf("youtube: duration enrichment failed (non-fatal): %s", redact(err.Error()))
		}
	}

	results := make([]YoutubeVideo, 0, len(videoIDs))
	for _, id := range videoIDs {
		results = append(results, byID[id])
	}

	rank(results)

	if len(results) > c.maxResults {
		results = results[:c.maxResults]
	}
	return results, nil
}

// nextAvailableKey returns the next key that isn't in cooldown, rotating
// currentIdx forward so load spreads across keys over time (not just on
// failure). Returns ok=false if every key is currently blocked.
func (c *Client) nextAvailableKey() (int, string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	n := len(c.apiKeys)
	for i := 0; i < n; i++ {
		idx := (c.currentIdx + i) % n
		if until, blocked := c.blockedUntil[idx]; blocked && time.Now().UTC().Before(until) {
			continue
		}
		c.currentIdx = (idx + 1) % n // advance for next call (round-robin)
		return idx, c.apiKeys[idx], true
	}
	return 0, "", false
}

func (c *Client) markBlocked(idx int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	// YouTube daily quota resets at midnight Pacific time; a short cooldown
	// here just prevents hammering the same exhausted key within this
	// process's lifetime - restart or next day naturally clears it.
	c.blockedUntil[idx] = time.Now().UTC().Add(6 * time.Hour)
}

func isQuotaError(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(err.Error(), "quota/rate limit")
}

// getWithRetry performs up to 3 attempts with exponential backoff for a
// single key/URL. Quota/rate-limit responses (429/403) are surfaced
// immediately (as a distinguishable error) so Search() can rotate keys
// instead of wasting retries on an exhausted key.
//
// SECURITY: fullURL contains the live API key as a query parameter (the
// YouTube Data API requires this). Neither the returned error nor any log
// line in this function may ever include fullURL or the raw client error
// verbatim - both are passed through redact() first, since a *url.Error
// from httpClient.Do would otherwise embed the whole URL (key included).
func (c *Client) getWithRetry(ctx context.Context, fullURL string, out interface{}) error {
	var lastErr error
	backoff := 500 * time.Millisecond

	for attempt := 1; attempt <= 3; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, fullURL, nil)
		if err != nil {
			return fmt.Errorf("youtube: failed to build request: %s", redact(err.Error()))
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("youtube: request failed (attempt %d/3)", attempt)
			log.Printf("youtube: request error (attempt %d/3): %s", attempt, redact(err.Error()))
			if ctx.Err() != nil {
				return lastErr // context canceled/deadline exceeded - retrying won't help
			}
			time.Sleep(backoff)
			backoff *= 2
			continue
		}

		func() {
			defer resp.Body.Close()
			switch {
			case resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == 403:
				lastErr = fmt.Errorf("youtube: quota/rate limit hit (status %d)", resp.StatusCode)
			case resp.StatusCode >= 500:
				lastErr = fmt.Errorf("youtube: server error (status %d)", resp.StatusCode)
			case resp.StatusCode != http.StatusOK:
				lastErr = fmt.Errorf("youtube: unexpected status %d", resp.StatusCode)
			default:
				if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
					lastErr = fmt.Errorf("youtube: failed to parse response: %s", redact(err.Error()))
				} else {
					lastErr = nil
				}
			}
		}()

		if lastErr == nil {
			return nil
		}

		if isQuotaError(lastErr) {
			return lastErr // don't retry a quota error, let Search() rotate keys
		}

		log.Printf("youtube: attempt %d/3 failed: %s", attempt, redact(lastErr.Error()))
		time.Sleep(backoff)
		backoff *= 2
	}

	return lastErr
}

func isBlocked(title, description string) bool {
	t := strings.ToLower(title + " " + description)
	for _, kw := range blockedKeywords {
		if strings.Contains(t, kw) {
			return true
		}
	}
	return false
}

// rank sorts results so priority-channel videos appear first, preserving
// relative order otherwise (stable sort behavior via simple partition).
func rank(videos []YoutubeVideo) {
	isPriority := func(channel string) bool {
		for _, p := range PriorityChannels {
			if strings.Contains(strings.ToLower(channel), strings.ToLower(p)) {
				return true
			}
		}
		return false
	}

	priority := make([]YoutubeVideo, 0, len(videos))
	rest := make([]YoutubeVideo, 0, len(videos))
	for _, v := range videos {
		if isPriority(v.ChannelName) {
			priority = append(priority, v)
		} else {
			rest = append(rest, v)
		}
	}
	copy(videos, append(priority, rest...))
}

// formatISO8601Duration converts "PT12M45S" -> "12:45".
func formatISO8601Duration(iso string) string {
	iso = strings.TrimPrefix(iso, "PT")
	var h, m, s int
	num := ""
	for _, r := range iso {
		switch r {
		case 'H':
			fmt.Sscanf(num, "%d", &h)
			num = ""
		case 'M':
			fmt.Sscanf(num, "%d", &m)
			num = ""
		case 'S':
			fmt.Sscanf(num, "%d", &s)
			num = ""
		default:
			num += string(r)
		}
	}
	if h > 0 {
		return fmt.Sprintf("%d:%02d:%02d", h, m, s)
	}
	return fmt.Sprintf("%d:%02d", m, s)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/youtube/youtube_client.go"), $content_internal_youtube_youtube_client_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/youtube/youtube_client.go" -ForegroundColor Green

# --- internal/youtube/service.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/youtube") | Out-Null
$content_internal_youtube_service_go = @'
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

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/youtube/service.go"), $content_internal_youtube_service_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/youtube/service.go" -ForegroundColor Green

# --- internal/youtube/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/youtube") | Out-Null
$content_internal_youtube_handler_go = @'
package youtube

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/pkg/logger"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// RegisterRoutes wires this package's endpoints into an existing Gin router
// group, matching the same package-level pattern used by categories,
// subjects, lessons, etc. Call it from main.go like:
//
//	youtube.RegisterRoutes(api, youtubeHandler, authMiddleware)
//
// authMiddleware is your existing JWT middleware — this package does not
// implement or modify auth. Note: this adds routes UNDER the existing
// "/lessons" URL space (/api/lessons/:id/videos) but does not touch or
// re-register the lessons package's own routes/handler.
func RegisterRoutes(router gin.IRouter, h *Handler, authMiddleware gin.HandlerFunc) {
	lessonVideos := router.Group("/lessons")
	lessonVideos.Use(authMiddleware)
	{
		lessonVideos.GET("/:id/videos", h.GetLessonVideos)
		lessonVideos.POST("/:id/videos/progress", h.SaveVideoProgress)
	}

	videos := router.Group("/videos")
	videos.Use(authMiddleware)
	{
		videos.GET("/search", h.SearchVideos)
	}
}

// GetLessonVideos handles GET /api/lessons/:id/videos
func (h *Handler) GetLessonVideos(c *gin.Context) {
	lessonID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid lesson id"})
		return
	}

	videos, err := h.service.GetVideosForLesson(c.Request.Context(), lessonID)
	if err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "lesson not found"})
			return
		}
		// SECURITY: never forward err.Error() to the client - the underlying
		// YouTube client error can (rarely) still carry request context.
		// Full detail goes to the server log only.
		logger.Error("youtube: failed to fetch lesson videos", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch videos"})
		return
	}

	c.JSON(http.StatusOK, videos)
}

// SearchVideos handles GET /api/videos/search?q=
func (h *Handler) SearchVideos(c *gin.Context) {
	q := c.Query("q")
	if q == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing q parameter"})
		return
	}

	videos, err := h.service.SearchVideos(c.Request.Context(), q)
	if err != nil {
		if errors.Is(err, ErrEmptyQuery) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "missing q parameter"})
			return
		}
		// SECURITY: this is the exact endpoint the audit flagged (critical #2)
		// as leaking the YouTube API key via "details": err.Error(). Never
		// forward the raw error to the client - log it server-side instead.
		logger.Error("youtube: search failed", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
		return
	}

	c.JSON(http.StatusOK, videos)
}

// SaveVideoProgress handles POST /api/lessons/:id/videos/progress
// Expects the authenticated user id to be set on the context by your
// existing auth middleware under the key "user_id" (set by
// middleware.AuthMiddleware from the JWT claims).
func (h *Handler) SaveVideoProgress(c *gin.Context) {
	lessonID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid lesson id"})
		return
	}

	userIDVal, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthenticated"})
		return
	}

	var userID int64
	switch v := userIDVal.(type) {
	case int64:
		userID = v
	case int:
		userID = int64(v)
	case uint:
		userID = int64(v)
	case uint64:
		userID = int64(v)
	default:
		logger.Error("youtube: unexpected user_id type in context", nil)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}

	var req VideoProgressRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payload"})
		return
	}

	if err := h.service.RecordProgress(c.Request.Context(), userID, lessonID, req); err != nil {
		logger.Error("youtube: failed to save video progress", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save progress"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/youtube/handler.go"), $content_internal_youtube_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/youtube/handler.go" -ForegroundColor Green

# --- internal/youtube/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/youtube") | Out-Null
$content_internal_youtube_repository_go = @'
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

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/youtube/repository.go"), $content_internal_youtube_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/youtube/repository.go" -ForegroundColor Green

# --- internal/quiz/model.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/quiz") | Out-Null
$content_internal_quiz_model_go = @'
// Package quiz persists quiz attempts (both lesson-based and freeform
// AI-generated), grades them server-side, and computes analytics from
// real attempt data.
//
// Question types: lesson-based quizzes (from lesson_ai_content) always
// use "single_mcq" - unchanged from before. The freeform AI Quiz
// Generator additionally supports "multiple_mcq", "true_false",
// "fill_blank", and "short_answer". Match-the-following, assertion-
// reason, image-based, and numerical-answer questions are intentionally
// out of scope for now - they need substantially different UI.
package quiz

import "time"

// Supported question types for the freeform AI Quiz Generator.
const (
	QuestionTypeSingleMCQ   = "single_mcq"
	QuestionTypeMultipleMCQ = "multiple_mcq"
	QuestionTypeTrueFalse   = "true_false"
	QuestionTypeFillBlank   = "fill_blank"
	QuestionTypeShortAnswer = "short_answer"
)

// Attempt mirrors a "quiz_attempts" table row.
type Attempt struct {
	ID               int       `json:"id"`
	UserID           int       `json:"user_id"`
	LessonID         *int      `json:"lesson_id"`
	SubjectID        *int      `json:"subject_id"`
	Topic            string    `json:"topic"`
	TotalQuestions   int       `json:"total_questions"`
	CorrectCount     int       `json:"correct_count"`
	ScorePercent     int       `json:"score_percent"`
	TimeTakenSeconds *int      `json:"time_taken_seconds"`
	CreatedAt        time.Time `json:"created_at"`
}

// AttemptAnswer mirrors a "quiz_attempt_answers" table row, generalized
// to cover every supported question type. Only the fields relevant to a
// given QuestionType are populated.
type AttemptAnswer struct {
	ID              int      `json:"id"`
	AttemptID       int      `json:"attempt_id"`
	QuestionIndex   int      `json:"question_index"`
	QuestionType    string   `json:"question_type"`
	QuestionText    string   `json:"question_text"`
	Options         []string `json:"options,omitempty"`
	SelectedOption  *int     `json:"selected_option,omitempty"`
	CorrectOption   *int     `json:"correct_option,omitempty"`
	SelectedOptions []int    `json:"selected_options,omitempty"`
	CorrectOptions  []int    `json:"correct_options,omitempty"`
	SubmittedText   string   `json:"submitted_text,omitempty"`
	CorrectText     string   `json:"correct_text,omitempty"`
	Hint            string   `json:"hint,omitempty"`
	Explanation     string   `json:"explanation,omitempty"`
	DifficultyScore int      `json:"difficulty_score,omitempty"`
	IsCorrect       bool     `json:"is_correct"`
}

// AttemptWithAnswers is returned after submitting an attempt, and by the
// results/review screen.
type AttemptWithAnswers struct {
	Attempt
	Answers []AttemptAnswer `json:"answers"`
}

// SubmitLessonAttemptRequest is the body for POST /api/quiz/lessons/:id/attempt.
// Unchanged: lesson quizzes are always single_mcq, graded against the
// lesson's stored quiz_json.
type SubmitLessonAttemptRequest struct {
	Answers          []int `json:"answers" binding:"required"`
	TimeTakenSeconds int   `json:"time_taken_seconds"`
}

// FreeformQuestion is one AI-generated question. Internally (as stored in
// quiz_generated_sessions) it carries the full answer key. When returned
// to the client from /generate, CorrectOption/CorrectOptions/CorrectText/
// Explanation MUST be stripped first (see Handler.GenerateQuiz) - these
// four fields together ARE the answer key, and sending them to the client
// before the quiz is attempted is what let a tampered client score 100%
// (audit CRITICAL #3). Hint is safe to send upfront; Explanation is not,
// since it typically states the correct answer outright.
type FreeformQuestion struct {
	QuestionType    string   `json:"question_type"`
	Question        string   `json:"question"`
	Options         []string `json:"options,omitempty"`
	CorrectOption   *int     `json:"correct_option,omitempty"`
	CorrectOptions  []int    `json:"correct_options,omitempty"`
	CorrectText     string   `json:"correct_text,omitempty"`
	Hint            string   `json:"hint,omitempty"`
	Explanation     string   `json:"explanation,omitempty"`
	DifficultyScore int      `json:"difficulty_score,omitempty"`
}

// ForClient returns a copy with the answer-key fields stripped, safe to
// send to the client before the quiz has been attempted.
func (q FreeformQuestion) ForClient() FreeformQuestion {
	q.CorrectOption = nil
	q.CorrectOptions = nil
	q.CorrectText = ""
	q.Explanation = ""
	return q
}

// GenerateQuizResponse is the response body for POST /api/quiz/generate.
// QuizSessionID must be sent back unchanged in SubmitFreeformAttemptRequest
// so the server can grade against the answer key it stored at generation
// time, instead of trusting whatever the client echoes back.
type GenerateQuizResponse struct {
	QuizSessionID string             `json:"quiz_session_id"`
	Questions     []FreeformQuestion `json:"questions"`
}

// FreeformAnswered is one question index + the student's answer, sent back
// to /freeform/attempt for scoring and storage.
//
// SECURITY: any question_type/question/options/correct_option/
// correct_options/correct_text/hint/explanation/difficulty_score fields a
// client sends here are IGNORED for grading. They exist only for backward
// JSON compatibility with older payload shapes. Grading always reads the
// authoritative question (including the real answer key) back from the
// quiz_generated_sessions row identified by QuizSessionID on the parent
// request - never from this struct. Only SelectedOption/SelectedOptions/
// SubmittedText (the student's own input) are trusted from the client.
type FreeformAnswered struct {
	QuestionType    string   `json:"question_type,omitempty"`
	Question        string   `json:"question,omitempty"`
	Options         []string `json:"options,omitempty"`
	CorrectOption   *int     `json:"correct_option,omitempty"`
	CorrectOptions  []int    `json:"correct_options,omitempty"`
	CorrectText     string   `json:"correct_text,omitempty"`
	Hint            string   `json:"hint,omitempty"`
	Explanation     string   `json:"explanation,omitempty"`
	DifficultyScore int      `json:"difficulty_score,omitempty"`
	SelectedOption  *int     `json:"selected_option,omitempty"`
	SelectedOptions []int    `json:"selected_options,omitempty"`
	SubmittedText   string   `json:"submitted_text,omitempty"`
}

// SubmitFreeformAttemptRequest is the body for POST /api/quiz/freeform/attempt.
//
// QuizSessionID (returned by /generate as quiz_session_id) is now required:
// it's how the server locates the real, server-held answer key to grade
// against. This is an intentional, security-driven contract change - the
// Flutter client must be updated to (a) store quiz_session_id from the
// /generate response and (b) send it back here.
type SubmitFreeformAttemptRequest struct {
	QuizSessionID    string             `json:"quiz_session_id" binding:"required"`
	SubjectID        *int               `json:"subject_id"`
	Topic            string             `json:"topic" binding:"required"`
	TimeTakenSeconds int                `json:"time_taken_seconds"`
	Questions        []FreeformAnswered `json:"questions" binding:"required"`
}

// GenerateQuizRequest is the body for POST /api/quiz/generate.
// QuestionTypes selects which types to mix into the generated quiz -
// defaults to ["single_mcq"] if empty, so existing callers keep working
// unchanged.
type GenerateQuizRequest struct {
	SubjectID     *int     `json:"subject_id"`
	Topic         string   `json:"topic" binding:"required"`
	NumQuestions  int      `json:"num_questions"`
	Difficulty    string   `json:"difficulty"`     // "easy" | "medium" | "hard"
	QuestionTypes []string `json:"question_types"` // subset of the QuestionType* constants
}

// SubjectAccuracy is one row in the analytics response's per-subject breakdown.
type SubjectAccuracy struct {
	SubjectID   int     `json:"subject_id"`
	SubjectName string  `json:"subject_name"`
	Attempts    int     `json:"attempts"`
	Accuracy    float64 `json:"accuracy"` // 0-100
}

// DayAccuracy is one point in the weekly performance trend.
type DayAccuracy struct {
	Date     string  `json:"date"`
	Accuracy float64 `json:"accuracy"`
	Attempts int     `json:"attempts"`
}

// Analytics is the response for GET /api/quiz/analytics - all computed
// from the current user's real quiz_attempts rows. PassedCount/FailedCount
// use a 60% score threshold (same threshold used for "weak topics").
type Analytics struct {
	TotalAttempts   int               `json:"total_attempts"`
	OverallAccuracy float64           `json:"overall_accuracy"`
	PassedCount     int               `json:"passed_count"`
	FailedCount     int               `json:"failed_count"`
	AverageScore    float64           `json:"average_score"`
	HighestScore    int               `json:"highest_score"`
	BySubject       []SubjectAccuracy `json:"by_subject"`
	WeakTopics      []SubjectAccuracy `json:"weak_topics"`
	WeeklyTrend     []DayAccuracy     `json:"weekly_trend"`
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/quiz/model.go"), $content_internal_quiz_model_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/quiz/model.go" -ForegroundColor Green

# --- internal/quiz/service.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/quiz") | Out-Null
$content_internal_quiz_service_go = @'
package quiz

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"ai-tutor-backend/internal/ai"
	"ai-tutor-backend/internal/badge"
	"ai-tutor-backend/internal/certificate"
	"ai-tutor-backend/internal/streak"
	"ai-tutor-backend/internal/xp"
)

// ErrNoQuizForLesson is returned when a lesson has no AI-generated quiz yet.
var ErrNoQuizForLesson = errors.New("this lesson has no quiz yet")

// ErrAnswerCountMismatch is returned when the submitted answers array
// doesn't match the lesson's actual question count.
var ErrAnswerCountMismatch = errors.New("answers count does not match question count")

// ErrQuizSessionNotFound is returned when quiz_session_id doesn't match any
// stored session for this user, or the session has expired. Deliberately
// generic (doesn't distinguish "wrong user" from "expired" from "never
// existed") so it can't be used to enumerate other users' session IDs.
var ErrQuizSessionNotFound = errors.New("quiz session not found or expired")

// generatedQuizTTL is how long a generated quiz's answer key is retained
// server-side, waiting for the matching /freeform/attempt submission.
const generatedQuizTTL = 2 * time.Hour

var allQuestionTypes = []string{
	QuestionTypeSingleMCQ, QuestionTypeMultipleMCQ, QuestionTypeTrueFalse,
	QuestionTypeFillBlank, QuestionTypeShortAnswer,
}

// Service contains the business logic for quiz attempts, grading,
// analytics, and AI quiz generation.
type Service struct {
	repo       *Repository
	groqClient *ai.GroqClient
	streakSvc  *streak.Service
	badgeSvc   *badge.Service
	xpSvc      *xp.Service
	certSvc    *certificate.Service
}

// NewService wires a Repository, the shared GroqClient, the shared
// streak Service, and the shared badge Service into a quiz Service.
func NewService(repo *Repository, groqClient *ai.GroqClient, streakSvc *streak.Service, badgeSvc *badge.Service, xpSvc *xp.Service, certSvc *certificate.Service) *Service {
	return &Service{repo: repo, groqClient: groqClient, streakSvc: streakSvc, badgeSvc: badgeSvc, xpSvc: xpSvc, certSvc: certSvc}
}

// SubmitLessonAttempt grades a lesson-based quiz attempt server-side
// (using the lesson's stored quiz_json as the answer key) and persists
// it. Lesson quizzes are always single_mcq, unchanged from before.
func (s *Service) SubmitLessonAttempt(userID, lessonID int, req SubmitLessonAttemptRequest) (*AttemptWithAnswers, error) {
	questions, err := s.repo.GetLessonQuiz(lessonID)
	if err != nil {
		return nil, err
	}
	if len(questions) == 0 {
		return nil, ErrNoQuizForLesson
	}
	if len(req.Answers) != len(questions) {
		return nil, ErrAnswerCountMismatch
	}

	subjectID, err := s.repo.GetLessonSubjectID(lessonID)
	if err != nil {
		return nil, err
	}

	answers := make([]AttemptAnswer, len(questions))
	for i, q := range questions {
		selected := req.Answers[i]
		var selectedPtr *int
		if selected >= 0 {
			selectedPtr = &selected
		}
		correctOption := q.CorrectOption
		answers[i] = AttemptAnswer{
			QuestionIndex:  i,
			QuestionType:   QuestionTypeSingleMCQ,
			QuestionText:   q.Question,
			Options:        q.Options,
			SelectedOption: selectedPtr,
			CorrectOption:  &correctOption,
			IsCorrect:      selectedPtr != nil && *selectedPtr == q.CorrectOption,
		}
	}

	lid := lessonID
	sid := subjectID
	attemptID, err := s.repo.SaveAttempt(userID, &lid, &sid, "", req.TimeTakenSeconds, answers)
	if err != nil {
		return nil, err
	}
	_ = s.streakSvc.RecordActivity(userID) // best-effort
	go s.badgeSvc.CheckAndAwardBadges(userID)
	go s.xpSvc.AwardQuizCompletion(userID, attemptID)
	go s.xpSvc.OnStudyActivity(userID)
	go s.certSvc.CheckAndGenerate(userID, subjectID)

	return s.repo.GetAttemptWithAnswers(userID, attemptID)
}

// SubmitFreeformAttempt grades and persists an AI-generated quiz that
// isn't tied to a specific lesson.
//
// SECURITY (fixes audit CRITICAL #3): grading is done ENTIRELY against the
// server-held answer key fetched via req.QuizSessionID (persisted at
// /generate time in quiz_generated_sessions). The client's own
// question/correct_option/correct_options/correct_text/etc. fields in
// req.Questions are never read for grading - only SelectedOption/
// SelectedOptions/SubmittedText (the student's actual answer) are used.
// This closes the "tampered client scores 100% and farms XP/badges/
// certificates" hole, since a client can no longer supply its own answer
// key.
func (s *Service) SubmitFreeformAttempt(userID int, req SubmitFreeformAttemptRequest) (*AttemptWithAnswers, error) {
	if strings.TrimSpace(req.QuizSessionID) == "" {
		return nil, ErrQuizSessionNotFound
	}
	if len(req.Questions) == 0 {
		return nil, errors.New("at least one question is required")
	}

	stored, storedSubjectID, err := s.repo.GetGeneratedQuiz(req.QuizSessionID, userID)
	if err != nil {
		return nil, err
	}
	if len(req.Questions) != len(stored) {
		return nil, ErrAnswerCountMismatch
	}

	subjectID := req.SubjectID
	if subjectID == nil {
		subjectID = storedSubjectID
	}

	answers := make([]AttemptAnswer, len(stored))
	for i, authoritative := range stored {
		client := req.Questions[i]

		qType := authoritative.QuestionType
		if qType == "" {
			qType = QuestionTypeSingleMCQ
		}

		answer := AttemptAnswer{
			QuestionIndex:   i,
			QuestionType:    qType,
			QuestionText:    authoritative.Question,
			Options:         authoritative.Options,
			CorrectOption:   authoritative.CorrectOption,
			CorrectOptions:  authoritative.CorrectOptions,
			CorrectText:     authoritative.CorrectText,
			Hint:            authoritative.Hint,
			Explanation:     authoritative.Explanation,
			DifficultyScore: authoritative.DifficultyScore,
			// Only these three come from the client - the student's own input.
			SelectedOption:  client.SelectedOption,
			SelectedOptions: client.SelectedOptions,
			SubmittedText:   client.SubmittedText,
		}

		switch qType {
		case QuestionTypeMultipleMCQ:
			answer.IsCorrect = intSetsEqual(client.SelectedOptions, authoritative.CorrectOptions)
		case QuestionTypeFillBlank, QuestionTypeShortAnswer:
			answer.IsCorrect = authoritative.CorrectText != "" &&
				normalizeAnswerText(client.SubmittedText) == normalizeAnswerText(authoritative.CorrectText)
		default: // single_mcq, true_false
			answer.IsCorrect = client.SelectedOption != nil && authoritative.CorrectOption != nil &&
				*client.SelectedOption == *authoritative.CorrectOption
		}

		answers[i] = answer
	}

	attemptID, err := s.repo.SaveAttempt(userID, nil, subjectID, req.Topic, req.TimeTakenSeconds, answers)
	if err != nil {
		return nil, err
	}

	// Single-use: consume the session so the same generated answer key
	// can't be resubmitted repeatedly to farm XP/badges. Best-effort - a
	// failure here shouldn't fail the (already-saved) attempt.
	_ = s.repo.DeleteGeneratedQuiz(req.QuizSessionID)

	_ = s.streakSvc.RecordActivity(userID) // best-effort
	go s.badgeSvc.CheckAndAwardBadges(userID)
	go s.xpSvc.AwardQuizCompletion(userID, attemptID)
	go s.xpSvc.OnStudyActivity(userID)
	if subjectID != nil {
		go s.certSvc.CheckAndGenerate(userID, *subjectID)
	}
	return s.repo.GetAttemptWithAnswers(userID, attemptID)
}

func intSetsEqual(a, b []int) bool {
	if len(a) != len(b) || len(a) == 0 {
		return false
	}
	ac := append([]int{}, a...)
	bc := append([]int{}, b...)
	sort.Ints(ac)
	sort.Ints(bc)
	for i := range ac {
		if ac[i] != bc[i] {
			return false
		}
	}
	return true
}

func normalizeAnswerText(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

// ListAttempts returns a user's quiz history.
func (s *Service) ListAttempts(userID, lessonID int) ([]Attempt, error) {
	return s.repo.ListAttempts(userID, lessonID)
}

// GetAttempt returns one attempt with its full per-question breakdown.
func (s *Service) GetAttempt(userID, attemptID int) (*AttemptWithAnswers, error) {
	return s.repo.GetAttemptWithAnswers(userID, attemptID)
}

// GetAnalytics returns accuracy analytics computed from real attempt data.
func (s *Service) GetAnalytics(userID int) (*Analytics, error) {
	return s.repo.GetAnalytics(userID)
}

// GenerateQuiz asks Groq for a fresh set of quiz questions on a topic,
// mixing in whichever question types were requested (defaulting to
// single_mcq only, so existing callers are unaffected), persists the full
// answer key server-side keyed by a new session ID, and returns that
// session ID alongside the CLIENT-SAFE (answer-key-stripped) questions.
func (s *Service) GenerateQuiz(ctx context.Context, userID int, req GenerateQuizRequest) (string, []FreeformQuestion, error) {
	numQuestions := req.NumQuestions
	if numQuestions <= 0 {
		numQuestions = 5
	}
	if numQuestions > 10 {
		numQuestions = 10
	}
	difficulty := req.Difficulty
	if difficulty == "" {
		difficulty = "medium"
	}

	questionTypes := sanitizeQuestionTypes(req.QuestionTypes)

	assignments := make([]string, numQuestions)
	for i := 0; i < numQuestions; i++ {
		assignments[i] = questionTypes[i%len(questionTypes)]
	}
	var assignmentLines strings.Builder
	for i, t := range assignments {
		assignmentLines.WriteString(fmt.Sprintf("Question %d MUST have \"question_type\": \"%s\"\n", i+1, t))
	}

	systemPrompt := "You are an expert exam-prep quiz writer. You output ONLY raw JSON - no markdown code fences, no preamble. You follow the exact question_type assigned to each question - you never substitute a different type."
	userPrompt := fmt.Sprintf(`Generate exactly %d quiz questions about "%s" at %s difficulty.

Question type assignment (follow exactly, in this order):
%s
Return ONLY a JSON array of %d elements, in the same order as the assignment above. Each element's shape depends on its "question_type":

- "single_mcq" or "true_false": {"question_type": "...", "question": "...", "options": ["...", "...", "...", "..."], "correct_option": 0, "hint": "...", "explanation": "...", "difficulty_score": 5}
  (true_false must have exactly 2 options: "True" and "False")
- "multiple_mcq": {"question_type": "multiple_mcq", "question": "...", "options": ["...", "...", "...", "..."], "correct_options": [0, 2], "hint": "...", "explanation": "...", "difficulty_score": 5}
  (multiple_mcq must have at least 2 correct_options - if you can only think of 1 correct answer, pick a different question)
- "fill_blank" or "short_answer": {"question_type": "...", "question": "... (use ____ for the blank if fill_blank)", "correct_text": "the expected answer", "hint": "...", "explanation": "...", "difficulty_score": 5}
  (do NOT include an "options" field for these two types)

Rules:
- The "question_type" in your output for question N must exactly match the assignment above for question N - do not default to single_mcq.
- correct_option / correct_options are 0-based indices into "options".
- difficulty_score is 1-10 (1=very easy, 10=very hard), consistent with "%s" difficulty.
- hint must not give away the answer directly.
- Output nothing but the JSON array of exactly %d elements.`, numQuestions, req.Topic, difficulty, assignmentLines.String(), numQuestions, difficulty, numQuestions)

	messages := []ai.ChatCompletionMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	raw, err := s.groqClient.Chat(ctx, messages)
	if err != nil {
		return "", nil, err
	}

	clean := strings.TrimSpace(raw)
	clean = strings.TrimPrefix(clean, "```json")
	clean = strings.TrimPrefix(clean, "```")
	clean = strings.TrimSuffix(clean, "```")
	clean = strings.TrimSpace(clean)

	var questions []FreeformQuestion
	if err := json.Unmarshal([]byte(clean), &questions); err != nil {
		return "", nil, fmt.Errorf("invalid JSON from Groq: %w", err)
	}

	for i := range questions {
		if i < len(assignments) {
			questions[i].QuestionType = assignments[i]
		} else if questions[i].QuestionType == "" {
			questions[i].QuestionType = QuestionTypeSingleMCQ
		}
		if questions[i].DifficultyScore == 0 {
			questions[i].DifficultyScore = 5
		}
	}

	sessionID, err := s.repo.SaveGeneratedQuiz(userID, req.Topic, req.SubjectID, questions, generatedQuizTTL)
	if err != nil {
		return "", nil, fmt.Errorf("failed to persist quiz answer key: %w", err)
	}

	clientQuestions := make([]FreeformQuestion, len(questions))
	for i, q := range questions {
		clientQuestions[i] = q.ForClient()
	}

	return sessionID, clientQuestions, nil
}

func sanitizeQuestionTypes(requested []string) []string {
	if len(requested) == 0 {
		return []string{QuestionTypeSingleMCQ}
	}
	valid := map[string]bool{}
	for _, t := range allQuestionTypes {
		valid[t] = true
	}
	var result []string
	for _, t := range requested {
		if valid[t] {
			result = append(result, t)
		}
	}
	if len(result) == 0 {
		return []string{QuestionTypeSingleMCQ}
	}
	return result
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/quiz/service.go"), $content_internal_quiz_service_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/quiz/service.go" -ForegroundColor Green

# --- internal/quiz/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/quiz") | Out-Null
$content_internal_quiz_repository_go = @'
package quiz

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"sort"
	"time"
)

// Repository handles direct SQL access for quiz attempts and analytics.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a quiz Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// LessonQuizQuestion mirrors one entry from lesson_ai_content.quiz_json -
// always single-correct MCQ, unchanged from before.
type LessonQuizQuestion struct {
	Question      string   `json:"question"`
	Options       []string `json:"options"`
	CorrectOption int      `json:"correct_option"`
}

// GetLessonQuiz fetches the quiz questions stored for a lesson, or nil if
// the lesson has no AI content / quiz yet.
func (r *Repository) GetLessonQuiz(lessonID int) ([]LessonQuizQuestion, error) {
	var raw []byte
	err := r.db.QueryRow(`SELECT quiz_json FROM lesson_ai_content WHERE lesson_id = $1`, lessonID).Scan(&raw)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var questions []LessonQuizQuestion
	if err := json.Unmarshal(raw, &questions); err != nil {
		return nil, err
	}
	return questions, nil
}

// GetLessonSubjectID resolves a lesson's subject_id, to tag the attempt
// for subject-level analytics.
func (r *Repository) GetLessonSubjectID(lessonID int) (int, error) {
	var subjectID int
	err := r.db.QueryRow(`SELECT subject_id FROM lessons WHERE id = $1`, lessonID).Scan(&subjectID)
	return subjectID, err
}

// --- Generated-quiz answer-key session store ------------------------------
//
// Fixes audit CRITICAL #3: freeform quizzes previously had no server-side
// record of the correct answers, so grading trusted whatever "correct_*"
// fields the client echoed back. GenerateQuiz now persists the real,
// AI-generated answer key here (keyed by an unguessable session ID) at
// /generate time, and SubmitFreeformAttempt reads it back at grading time -
// the client is never trusted with the answer key before it submits.

// SaveGeneratedQuiz persists the full (answer-key-included) question set
// for a freeform quiz, returning a new unguessable session ID.
func (r *Repository) SaveGeneratedQuiz(userID int, topic string, subjectID *int, questions []FreeformQuestion, ttl time.Duration) (string, error) {
	sessionID, err := newSessionID()
	if err != nil {
		return "", err
	}

	payload, err := json.Marshal(questions)
	if err != nil {
		return "", err
	}

	now := time.Now().UTC()
	const q = `
		INSERT INTO quiz_generated_sessions (id, user_id, topic, subject_id, questions_json, created_at, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`
	if _, err := r.db.Exec(q, sessionID, userID, topic, subjectID, payload, now, now.Add(ttl)); err != nil {
		return "", err
	}
	return sessionID, nil
}

// GetGeneratedQuiz looks up a previously-generated answer key by session
// ID, verifying it belongs to userID and hasn't expired. Returns
// ErrQuizSessionNotFound (never a raw sql.ErrNoRows or DB detail) for any
// "doesn't exist / wrong user / expired" case, so a caller can't use the
// error to probe for valid session IDs belonging to other users.
func (r *Repository) GetGeneratedQuiz(sessionID string, userID int) ([]FreeformQuestion, *int, error) {
	const q = `
		SELECT subject_id, questions_json
		FROM quiz_generated_sessions
		WHERE id = $1 AND user_id = $2 AND expires_at > now()`

	var subjectID sql.NullInt64
	var raw []byte
	err := r.db.QueryRow(q, sessionID, userID).Scan(&subjectID, &raw)
	if err == sql.ErrNoRows {
		return nil, nil, ErrQuizSessionNotFound
	}
	if err != nil {
		return nil, nil, err
	}

	var questions []FreeformQuestion
	if err := json.Unmarshal(raw, &questions); err != nil {
		return nil, nil, err
	}

	var subjectIDPtr *int
	if subjectID.Valid {
		v := int(subjectID.Int64)
		subjectIDPtr = &v
	}
	return questions, subjectIDPtr, nil
}

// DeleteGeneratedQuiz removes a session after it's been graded (single-use)
// so the same server-held answer key can't be resubmitted repeatedly.
func (r *Repository) DeleteGeneratedQuiz(sessionID string) error {
	_, err := r.db.Exec(`DELETE FROM quiz_generated_sessions WHERE id = $1`, sessionID)
	return err
}

func newSessionID() (string, error) {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// --- Attempts --------------------------------------------------------------

// nullableJSON marshals a slice to JSON, returning nil (-> SQL NULL) for
// an empty/nil slice instead of the literal string "[]", so optional
// per-type columns (correct_options, selected_options) stay genuinely
// empty for question types that don't use them.
func nullableJSON(v interface{}) ([]byte, error) {
	switch t := v.(type) {
	case []int:
		if len(t) == 0 {
			return nil, nil
		}
	case []string:
		if len(t) == 0 {
			return nil, nil
		}
	}
	return json.Marshal(v)
}

// SaveAttempt inserts the attempt row and its per-question answers in one
// transaction, returning the new attempt ID.
func (r *Repository) SaveAttempt(userID int, lessonID, subjectID *int, topic string, timeTakenSeconds int, answers []AttemptAnswer) (int, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	correctCount := 0
	for _, a := range answers {
		if a.IsCorrect {
			correctCount++
		}
	}
	total := len(answers)
	scorePercent := 0
	if total > 0 {
		scorePercent = (correctCount * 100) / total
	}

	var attemptID int
	err = tx.QueryRow(`
		INSERT INTO quiz_attempts (user_id, lesson_id, subject_id, topic, total_questions, correct_count, score_percent, time_taken_seconds)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id`,
		userID, lessonID, subjectID, topic, total, correctCount, scorePercent, timeTakenSeconds,
	).Scan(&attemptID)
	if err != nil {
		return 0, err
	}

	for _, a := range answers {
		optionsJSON, err := nullableJSON(a.Options)
		if err != nil {
			return 0, err
		}
		correctOptionsJSON, err := nullableJSON(a.CorrectOptions)
		if err != nil {
			return 0, err
		}
		selectedOptionsJSON, err := nullableJSON(a.SelectedOptions)
		if err != nil {
			return 0, err
		}

		questionType := a.QuestionType
		if questionType == "" {
			questionType = QuestionTypeSingleMCQ
		}

		res, err := tx.Exec(`
			INSERT INTO quiz_attempt_answers
				(attempt_id, question_index, question_type, question_text, options,
				 selected_option, correct_option, correct_options, selected_options,
				 submitted_text, correct_text, hint, explanation, difficulty_score, is_correct)
			VALUES ($1, $2, $3, $4, COALESCE($5, '[]'::jsonb), $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
			attemptID, a.QuestionIndex, questionType, a.QuestionText, optionsJSON,
			a.SelectedOption, a.CorrectOption, correctOptionsJSON, selectedOptionsJSON,
			a.SubmittedText, a.CorrectText, a.Hint, a.Explanation, nullIfZero(a.DifficultyScore), a.IsCorrect,
		)
		if err != nil {
			return 0, err
		}
		if n, rerr := res.RowsAffected(); rerr == nil && n == 0 {
			return 0, sql.ErrNoRows
		}
	}

	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return attemptID, nil
}

func nullIfZero(n int) interface{} {
	if n == 0 {
		return nil
	}
	return n
}

// ListAttempts returns a user's attempt history (most recent first),
// optionally filtered by lessonID (pass 0 for no filter).
func (r *Repository) ListAttempts(userID, lessonID int) ([]Attempt, error) {
	query := `
		SELECT id, user_id, lesson_id, subject_id, topic, total_questions, correct_count, score_percent, time_taken_seconds, created_at
		FROM quiz_attempts
		WHERE user_id = $1`
	args := []interface{}{userID}
	if lessonID > 0 {
		query += ` AND lesson_id = $2`
		args = append(args, lessonID)
	}
	query += ` ORDER BY created_at DESC`

	rows, err := r.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Attempt
	for rows.Next() {
		var a Attempt
		if err := rows.Scan(&a.ID, &a.UserID, &a.LessonID, &a.SubjectID, &a.Topic, &a.TotalQuestions, &a.CorrectCount, &a.ScorePercent, &a.TimeTakenSeconds, &a.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, a)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// GetAttemptWithAnswers returns one attempt (verifying ownership) plus its
// full per-question breakdown, for the results/review screen.
func (r *Repository) GetAttemptWithAnswers(userID, attemptID int) (*AttemptWithAnswers, error) {
	var a Attempt
	err := r.db.QueryRow(`
		SELECT id, user_id, lesson_id, subject_id, topic, total_questions, correct_count, score_percent, time_taken_seconds, created_at
		FROM quiz_attempts WHERE id = $1 AND user_id = $2`, attemptID, userID,
	).Scan(&a.ID, &a.UserID, &a.LessonID, &a.SubjectID, &a.Topic, &a.TotalQuestions, &a.CorrectCount, &a.ScorePercent, &a.TimeTakenSeconds, &a.CreatedAt)
	if err != nil {
		return nil, err
	}

	rows, err := r.db.Query(`
		SELECT id, attempt_id, question_index, question_type, question_text, options,
		       selected_option, correct_option, correct_options, selected_options,
		       submitted_text, correct_text, hint, explanation, difficulty_score, is_correct
		FROM quiz_attempt_answers WHERE attempt_id = $1 ORDER BY question_index`, attemptID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var answers []AttemptAnswer
	for rows.Next() {
		var ans AttemptAnswer
		var optionsRaw, correctOptionsRaw, selectedOptionsRaw []byte
		var submittedText, correctText, hint, explanation sql.NullString
		var difficultyScore sql.NullInt64

		if err := rows.Scan(
			&ans.ID, &ans.AttemptID, &ans.QuestionIndex, &ans.QuestionType, &ans.QuestionText, &optionsRaw,
			&ans.SelectedOption, &ans.CorrectOption, &correctOptionsRaw, &selectedOptionsRaw,
			&submittedText, &correctText, &hint, &explanation, &difficultyScore, &ans.IsCorrect,
		); err != nil {
			return nil, err
		}

		if len(optionsRaw) > 0 {
			_ = json.Unmarshal(optionsRaw, &ans.Options)
		}
		if len(correctOptionsRaw) > 0 {
			_ = json.Unmarshal(correctOptionsRaw, &ans.CorrectOptions)
		}
		if len(selectedOptionsRaw) > 0 {
			_ = json.Unmarshal(selectedOptionsRaw, &ans.SelectedOptions)
		}
		ans.SubmittedText = submittedText.String
		ans.CorrectText = correctText.String
		ans.Hint = hint.String
		ans.Explanation = explanation.String
		if difficultyScore.Valid {
			ans.DifficultyScore = int(difficultyScore.Int64)
		}

		answers = append(answers, ans)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return &AttemptWithAnswers{Attempt: a, Answers: answers}, nil
}

// GetAnalytics computes overall + per-subject accuracy from real attempt
// data - nothing here is fabricated or hardcoded. Date bucketing for the
// weekly trend is computed in Go using UTC (rather than relying solely on
// Postgres's CURRENT_DATE, which follows the session/server timezone) so
// "today" is consistent with the rest of the app's UTC-based logic (streaks,
// etc).
func (r *Repository) GetAnalytics(userID int) (*Analytics, error) {
	analytics := &Analytics{}

	var totalCorrect, totalQuestions int
	err := r.db.QueryRow(`
		SELECT COUNT(*), COALESCE(SUM(correct_count), 0), COALESCE(SUM(total_questions), 0)
		FROM quiz_attempts WHERE user_id = $1`, userID,
	).Scan(&analytics.TotalAttempts, &totalCorrect, &totalQuestions)
	if err != nil {
		return nil, err
	}
	if totalQuestions > 0 {
		analytics.OverallAccuracy = (float64(totalCorrect) / float64(totalQuestions)) * 100
	}

	// Passed/failed (60% threshold), average score, highest score - all
	// derived directly from each attempt's stored score_percent.
	const passThreshold = 60
	scoreRows, err := r.db.Query(`SELECT score_percent FROM quiz_attempts WHERE user_id = $1`, userID)
	if err != nil {
		return nil, err
	}
	var scoreSum, scoreCount, highest int
	for scoreRows.Next() {
		var score int
		if err := scoreRows.Scan(&score); err != nil {
			scoreRows.Close()
			return nil, err
		}
		scoreSum += score
		scoreCount++
		if score > highest {
			highest = score
		}
		if score >= passThreshold {
			analytics.PassedCount++
		} else {
			analytics.FailedCount++
		}
	}
	if err := scoreRows.Err(); err != nil {
		scoreRows.Close()
		return nil, err
	}
	scoreRows.Close()
	if scoreCount > 0 {
		analytics.AverageScore = float64(scoreSum) / float64(scoreCount)
	}
	analytics.HighestScore = highest

	// Weekly trend: one accuracy point per day for the last 7 UTC days.
	// The 7-day window boundary is computed here in Go (UTC) and passed as
	// a bound parameter, instead of letting Postgres's CURRENT_DATE (which
	// follows the DB server's configured timezone) decide what "today" is.
	today := time.Now().UTC().Truncate(24 * time.Hour)
	windowStart := today.AddDate(0, 0, -6)

	trendRows, err := r.db.Query(`
		SELECT (created_at AT TIME ZONE 'utc')::date AS day, COUNT(*), COALESCE(SUM(correct_count), 0), COALESCE(SUM(total_questions), 0)
		FROM quiz_attempts
		WHERE user_id = $1 AND created_at >= $2
		GROUP BY day
		ORDER BY day`, userID, windowStart)
	if err != nil {
		return nil, err
	}
	dayMap := map[string]DayAccuracy{}
	for trendRows.Next() {
		var date time.Time
		var attempts, correct, questions int
		if err := trendRows.Scan(&date, &attempts, &correct, &questions); err != nil {
			trendRows.Close()
			return nil, err
		}
		acc := 0.0
		if questions > 0 {
			acc = (float64(correct) / float64(questions)) * 100
		}
		key := date.Format("2006-01-02")
		dayMap[key] = DayAccuracy{Date: key, Accuracy: acc, Attempts: attempts}
	}
	if err := trendRows.Err(); err != nil {
		trendRows.Close()
		return nil, err
	}
	trendRows.Close()

	for i := 6; i >= 0; i-- {
		day := today.AddDate(0, 0, -i)
		key := day.Format("2006-01-02")
		if d, ok := dayMap[key]; ok {
			analytics.WeeklyTrend = append(analytics.WeeklyTrend, d)
		} else {
			analytics.WeeklyTrend = append(analytics.WeeklyTrend, DayAccuracy{Date: key, Accuracy: 0, Attempts: 0})
		}
	}

	rows, err := r.db.Query(`
		SELECT s.id, s.name, COUNT(qa.id), COALESCE(SUM(qa.correct_count), 0), COALESCE(SUM(qa.total_questions), 0)
		FROM quiz_attempts qa
		JOIN subjects s ON s.id = qa.subject_id
		WHERE qa.user_id = $1
		GROUP BY s.id, s.name
		ORDER BY s.name`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var sa SubjectAccuracy
		var correct, questions int
		if err := rows.Scan(&sa.SubjectID, &sa.SubjectName, &sa.Attempts, &correct, &questions); err != nil {
			return nil, err
		}
		if questions > 0 {
			sa.Accuracy = (float64(correct) / float64(questions)) * 100
		}
		analytics.BySubject = append(analytics.BySubject, sa)
		if sa.Accuracy < 60 {
			analytics.WeakTopics = append(analytics.WeakTopics, sa)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	sort.Slice(analytics.WeakTopics, func(i, j int) bool {
		return analytics.WeakTopics[i].Accuracy < analytics.WeakTopics[j].Accuracy
	})

	return analytics, nil
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/quiz/repository.go"), $content_internal_quiz_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/quiz/repository.go" -ForegroundColor Green

# --- internal/quiz/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/quiz") | Out-Null
$content_internal_quiz_handler_go = @'
package quiz

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/pkg/logger"
	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the quiz Service.
type Handler struct {
	service *Service
}

// NewHandler builds a quiz Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// SubmitLessonAttempt handles POST /api/quiz/lessons/:id/attempt.
func (h *Handler) SubmitLessonAttempt(c *gin.Context) {
	lessonID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}

	var req SubmitLessonAttemptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "answers array is required")
		return
	}

	userID := c.GetInt("user_id")

	result, err := h.service.SubmitLessonAttempt(userID, lessonID, req)
	if err != nil {
		switch {
		case errors.Is(err, ErrNoQuizForLesson):
			utils.RespondError(c, http.StatusNotFound, "This lesson has no quiz yet")
		case errors.Is(err, ErrAnswerCountMismatch):
			utils.RespondError(c, http.StatusBadRequest, "Number of answers does not match the quiz")
		default:
			logger.Error("quiz: SubmitLessonAttempt failed", err)
			utils.RespondError(c, http.StatusInternalServerError, "Failed to submit quiz attempt")
		}
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attempt recorded", result)
}

// SubmitFreeformAttempt handles POST /api/quiz/freeform/attempt.
//
// SECURITY: grading happens server-side against the answer key stored at
// /generate time (see Service.SubmitFreeformAttempt) - the request body's
// own correct_option/correct_options/correct_text fields are never
// trusted. quiz_session_id is required; requests missing/using an
// unknown/expired one are rejected rather than silently trusting the
// client's echoed answer key.
func (h *Handler) SubmitFreeformAttempt(c *gin.Context) {
	var req SubmitFreeformAttemptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "quiz_session_id, topic, and questions are required")
		return
	}

	userID := c.GetInt("user_id")

	result, err := h.service.SubmitFreeformAttempt(userID, req)
	if err != nil {
		switch {
		case errors.Is(err, ErrQuizSessionNotFound):
			utils.RespondError(c, http.StatusBadRequest, "This quiz session is invalid or has expired. Please generate a new quiz.")
		case errors.Is(err, ErrAnswerCountMismatch):
			utils.RespondError(c, http.StatusBadRequest, "Number of answers does not match the generated quiz")
		default:
			logger.Error("quiz: SubmitFreeformAttempt failed", err)
			utils.RespondError(c, http.StatusInternalServerError, "Failed to submit quiz attempt")
		}
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attempt recorded", result)
}

// ListAttempts handles GET /api/quiz/attempts?lesson_id=.
func (h *Handler) ListAttempts(c *gin.Context) {
	userID := c.GetInt("user_id")
	lessonID, _ := strconv.Atoi(c.Query("lesson_id"))

	list, err := h.service.ListAttempts(userID, lessonID)
	if err != nil {
		logger.Error("quiz: ListAttempts failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load quiz history")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attempts fetched", list)
}

// GetAttempt handles GET /api/quiz/attempts/:id.
func (h *Handler) GetAttempt(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid attempt id")
		return
	}

	userID := c.GetInt("user_id")

	result, err := h.service.GetAttempt(userID, id)
	if err != nil {
		utils.RespondError(c, http.StatusNotFound, "Attempt not found")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attempt fetched", result)
}

// GetAnalytics handles GET /api/quiz/analytics.
func (h *Handler) GetAnalytics(c *gin.Context) {
	userID := c.GetInt("user_id")

	result, err := h.service.GetAnalytics(userID)
	if err != nil {
		logger.Error("quiz: GetAnalytics failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load analytics")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Analytics fetched", result)
}

// GenerateQuiz handles POST /api/quiz/generate.
//
// Response shape change (security-driven, see model.go GenerateQuizResponse):
// "data" is now {"quiz_session_id": "...", "questions": [...]} instead of a
// bare questions array, and each question's correct_option/correct_options/
// correct_text/explanation are stripped. The Flutter client must store
// quiz_session_id and send it back in SubmitFreeformAttemptRequest.
func (h *Handler) GenerateQuiz(c *gin.Context) {
	var req GenerateQuizRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "topic is required")
		return
	}

	userID := c.GetInt("user_id")

	sessionID, questions, err := h.service.GenerateQuiz(c.Request.Context(), userID, req)
	if err != nil {
		logger.Error("quiz: GenerateQuiz failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to generate quiz. Please try again.")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Quiz generated", GenerateQuizResponse{
		QuizSessionID: sessionID,
		Questions:     questions,
	})
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/quiz/handler.go"), $content_internal_quiz_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/quiz/handler.go" -ForegroundColor Green

# --- migrations/028_quiz_session_store.sql ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "migrations") | Out-Null
$content_migrations_028_quiz_session_store_sql = @'
-- Migration: Server-side answer-key store for AI-generated freeform quizzes.
--
-- Fixes CRITICAL security issue found in the bug audit (20 July 2026):
-- freeform quiz answers were graded against a CLIENT-SUPPLIED answer key
-- (the /generate response included correct_option/correct_options/
-- correct_text, and /freeform/attempt just trusted whatever the client
-- echoed back) - so any tampered client could score 100% and farm XP,
-- badges, and certificates.
--
-- Generated questions (with their real answer key) are now persisted here
-- at /api/quiz/generate time, keyed by an unguessable session id. Grading
-- at /api/quiz/freeform/attempt reads the key back from this table -
-- never from the request body.

BEGIN;

CREATE TABLE IF NOT EXISTS quiz_generated_sessions (
    id             TEXT PRIMARY KEY,
    user_id        BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    topic          TEXT NOT NULL,
    subject_id     BIGINT,
    questions_json JSONB NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at     TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_quiz_generated_sessions_user_id ON quiz_generated_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_quiz_generated_sessions_expires_at ON quiz_generated_sessions(expires_at);

-- Optional: a periodic job (cron / pg_cron) can run this to sweep expired
-- sessions instead of letting the table grow unbounded:
--   DELETE FROM quiz_generated_sessions WHERE expires_at < now();

COMMIT;

'@
[System.IO.File]::WriteAllText((Join-Path $root "migrations/028_quiz_session_store.sql"), $content_migrations_028_quiz_session_store_sql, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote migrations/028_quiz_session_store.sql" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run migration: migrations/028_quiz_session_store.sql against your DB"
Write-Host "  2. cd backend; go build ./..."
Write-Host "  3. Update Flutter quiz_service.dart to store+send quiz_session_id (backend now requires it)"