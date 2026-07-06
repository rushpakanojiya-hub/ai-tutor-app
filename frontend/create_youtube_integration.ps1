# YouTube Integration - auto-generated file creator
# Run from the folder where you want the 'youtube-integration' project created
$ErrorActionPreference = 'Stop'
$root = Join-Path (Get-Location) 'youtube-integration'

function New-FileUtf8NoBom {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    Write-Host "Created: $Path"
}

$p_README_md = Join-Path $root 'README.md'
$content_p_README_md = @'
# YouTube Integration — AI Tutor App

Adds automatic educational YouTube videos per lesson:
`Lesson → AI Explanation → Recommended Videos → PDF Notes → Mark Complete`

Nothing in Auth, Categories, Subjects, Lessons (existing fields), Notes,
Search, Progress Tracking, AI Tutor, or the Dashboard is touched.

## 1. Database

Run `migrations/006_add_youtube_integration.sql` — **rename the number to
match your actual next migration number** in your migrations folder.

Adds:
- `lessons.youtube_search_query`, `lessons.youtube_enabled`
- `youtube_cache` table (24h TTL)
- `lesson_video_progress` table

## 2. Backend (Go)

Copy `backend/internal/youtube/` into your existing `internal/` folder as-is.

**go.mod**: no new dependency beyond what you already have (`github.com/gin-gonic/gin`,
`database/sql` + your existing Postgres driver, e.g. `lib/pq` or `pgx`).

**Environment variables** — add to `.env` / Render env:
```
YOUTUBE_API_KEY=your_key_here
YOUTUBE_MAX_RESULTS=5
```

**Wire it into your router** (wherever you currently register other route
groups, e.g. `main.go` or `routes.go`):

```go
import "yourmodule/internal/youtube"

db := /* your existing *sql.DB */
ytClient := youtube.NewClient(os.Getenv("YOUTUBE_API_KEY"), 5) // or parse YOUTUBE_MAX_RESULTS
ytRepo := youtube.NewRepository(db)
ytService := youtube.NewService(ytRepo, ytClient)
ytHandler := youtube.NewHandler(ytService)

api := router.Group("/api")
ytHandler.RegisterRoutes(api, yourExistingAuthMiddleware)
```

This adds:
- `GET /api/lessons/:id/videos`
- `GET /api/videos/search?q=`
- `POST /api/lessons/:id/videos/progress` (body: `video_id`, `watched_seconds`, `completed`)

`SaveVideoProgress` expects your auth middleware to set `c.Set("userID", <int64>)`
on the Gin context. If your middleware uses a different key/type, adjust the
one line in `handler.go` (`c.Get("userID")`).

### Files created
| File | Purpose |
|---|---|
| `model.go` | `YoutubeVideo`, `Lesson` (minimal projection), cache/progress structs |
| `youtube_client.go` | Direct HTTP client to YouTube Data API v3 — timeout, 3x retry w/ backoff, 429 rate-limit cooldown, channel-priority ranking, Shorts/music/gaming filtering, duration formatting |
| `search_generator.go` | Builds a search query from lesson title + subject when none is stored yet |
| `repository.go` | Reads lesson, reads/writes cache, upserts watch progress |
| `service.go` | Orchestrates: lesson → query → cache → API call → cache write, with fallback query retry |
| `handler.go` | Gin handlers + `RegisterRoutes` |

## 3. Flutter

Copy the 5 files into your existing `lib/` structure at the matching paths
(`models/`, `services/`, `providers/`, `widgets/`, `screens/`).

**pubspec.yaml** — add if not already present:
```yaml
dependencies:
  youtube_player_iframe: ^5.1.3
  provider: ^6.1.2       # skip if you're already on Riverpod — see note below
  flutter_animate: ^4.5.0 # you're already using this per your existing UI
  http: ^1.2.0
```

**Register the provider** in your existing `MultiProvider` (main.dart or
wherever providers are set up):

```dart
ChangeNotifierProvider(
  create: (_) => YoutubeProvider(
    YoutubeService(
      baseUrl: 'https://your-backend.onrender.com', // your existing base URL constant
      getAuthToken: () => yourAuthService.token,      // your existing token accessor
    ),
  ),
),
```

**Drop it into the lesson screen**, between AI Explanation and PDF Notes:

```dart
// existing: AI Explanation widget
LessonVideosScreen(lessonId: lesson.id, lessonTitle: lesson.title),
// existing: PDF Notes widget
```

> Note on Riverpod: if your app actually uses Riverpod (not Provider) for
> state, the `YoutubeProvider` class logic ports directly into a
> `StateNotifier<YoutubeState>` — same methods, same flow, just swap the
> base class and `notifyListeners()` for `state = state.copyWith(...)`.

### Files created
| File | Purpose |
|---|---|
| `models/youtube_video.dart` | `YoutubeVideo` model + JSON (de)serialization |
| `services/youtube_service.dart` | HTTP calls to the 3 backend endpoints |
| `providers/youtube_provider.dart` | Loading/loaded/empty/error state machine |
| `widgets/video_card.dart` | Pastel-styled card: thumbnail, duration badge, title, channel, Watch button |
| `screens/lesson_videos_screen.dart` | Skeleton loading, error+retry, empty state, video list, full player screen (play/pause/seek/fullscreen via `youtube_player_iframe`) |

## Not included (flag if you want these too)
- Admin UI to manually override `youtube_search_query` per lesson
- Rate-limit alerting/dashboard for YOUTUBE_API_KEY quota usage
- Landscape auto-rotation lock (currently relies on `youtube_player_iframe`'s
  built-in fullscreen; add `SystemChrome` orientation calls if you want forced
  landscape on fullscreen tap)

'@
New-FileUtf8NoBom -Path $p_README_md -Content $content_p_README_md

$p_backend_internal_youtube_model_go = Join-Path $root 'backend\internal\youtube\model.go'
$content_p_backend_internal_youtube_model_go = @'
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

'@
New-FileUtf8NoBom -Path $p_backend_internal_youtube_model_go -Content $content_p_backend_internal_youtube_model_go

$p_backend_internal_youtube_youtube_client_go = Join-Path $root 'backend\internal\youtube\youtube_client.go'
$content_p_backend_internal_youtube_youtube_client_go = @'
package youtube

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
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

// Client is a dedicated, self-contained YouTube Data API v3 client with
// timeout, retry, basic rate-limit backoff, and logging built in.
type Client struct {
	apiKey     string
	maxResults int
	httpClient *http.Client

	mu           sync.Mutex
	rateLimitHit time.Time
}

// NewClient builds a YouTube client. maxResults comes from YOUTUBE_MAX_RESULTS.
func NewClient(apiKey string, maxResults int) *Client {
	if maxResults <= 0 {
		maxResults = 5
	}
	return &Client{
		apiKey:     apiKey,
		maxResults: maxResults,
		httpClient: &http.Client{Timeout: 8 * time.Second},
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
		ID              string `json:"id"`
		ContentDetails  struct {
			Duration string `json:"duration"`
		} `json:"contentDetails"`
	} `json:"items"`
}

// Search queries YouTube for educational videos matching q, applies channel
// priority ranking and blocklist filtering, and enriches results with duration.
func (c *Client) Search(ctx context.Context, q string) ([]YoutubeVideo, error) {
	if c.apiKey == "" {
		return nil, fmt.Errorf("youtube: YOUTUBE_API_KEY is not configured")
	}
	if c.rateLimited() {
		return nil, fmt.Errorf("youtube: rate limit backoff active, try again shortly")
	}

	params := url.Values{}
	params.Set("part", "snippet")
	params.Set("q", q)
	params.Set("type", "video")
	params.Set("videoDuration", "medium") // excludes most Shorts (<4 min bucket is "short")
	params.Set("safeSearch", "strict")
	params.Set("relevanceLanguage", "en")
	params.Set("maxResults", fmt.Sprintf("%d", c.maxResults*2)) // over-fetch, then filter/rank
	params.Set("key", c.apiKey)

	var sr searchResponse
	if err := c.getWithRetry(ctx, youtubeSearchEndpoint+"?"+params.Encode(), &sr); err != nil {
		return nil, err
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
		if isBlocked(v.Title, v.Description) {
			continue
		}
		videoIDs = append(videoIDs, v.VideoID)
		byID[v.VideoID] = v
	}

	if len(videoIDs) == 0 {
		return []YoutubeVideo{}, nil
	}

	// Enrich with duration via videos.list (batched, 1 call).
	durParams := url.Values{}
	durParams.Set("part", "contentDetails")
	durParams.Set("id", strings.Join(videoIDs, ","))
	durParams.Set("key", c.apiKey)

	var vr videosResponse
	if err := c.getWithRetry(ctx, youtubeVideosEndpoint+"?"+durParams.Encode(), &vr); err == nil {
		for _, item := range vr.Items {
			if v, ok := byID[item.ID]; ok {
				v.Duration = formatISO8601Duration(item.ContentDetails.Duration)
				byID[item.ID] = v
			}
		}
	} else {
		log.Printf("youtube: duration enrichment failed (non-fatal): %v", err)
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

// getWithRetry performs up to 3 attempts with exponential backoff.
// Handles 429 (quota/rate limit) by marking a short backoff window.
func (c *Client) getWithRetry(ctx context.Context, fullURL string, out interface{}) error {
	var lastErr error
	backoff := 500 * time.Millisecond

	for attempt := 1; attempt <= 3; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, fullURL, nil)
		if err != nil {
			return err
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			lastErr = err
			log.Printf("youtube: request error (attempt %d/3): %v", attempt, err)
			time.Sleep(backoff)
			backoff *= 2
			continue
		}

		func() {
			defer resp.Body.Close()
			switch {
			case resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == 403:
				c.markRateLimited()
				lastErr = fmt.Errorf("youtube: quota/rate limit hit (status %d)", resp.StatusCode)
			case resp.StatusCode >= 500:
				lastErr = fmt.Errorf("youtube: server error (status %d)", resp.StatusCode)
			case resp.StatusCode != http.StatusOK:
				lastErr = fmt.Errorf("youtube: unexpected status %d", resp.StatusCode)
			default:
				lastErr = json.NewDecoder(resp.Body).Decode(out)
			}
		}()

		if lastErr == nil {
			return nil
		}

		log.Printf("youtube: attempt %d/3 failed: %v", attempt, lastErr)
		if strings.Contains(lastErr.Error(), "quota/rate limit") {
			break // don't burn attempts against an active quota block
		}
		time.Sleep(backoff)
		backoff *= 2
	}

	return lastErr
}

func (c *Client) markRateLimited() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.rateLimitHit = time.Now().Add(60 * time.Second)
}

func (c *Client) rateLimited() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return time.Now().Before(c.rateLimitHit)
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
New-FileUtf8NoBom -Path $p_backend_internal_youtube_youtube_client_go -Content $content_p_backend_internal_youtube_youtube_client_go

$p_backend_internal_youtube_search_generator_go = Join-Path $root 'backend\internal\youtube\search_generator.go'
$content_p_backend_internal_youtube_search_generator_go = @'
package youtube

import "fmt"

// GenerateSearchQuery builds an educational search query for a lesson when
// lessons.youtube_search_query is empty. This is a lightweight template-based
// generator (no AI Tutor / LLM dependency, per scope). If you later want
// smarter queries, plug an LLM call in here without touching AI Tutor code.
func GenerateSearchQuery(lessonTitle, subjectName string) string {
	if lessonTitle == "" {
		return subjectName + " educational video"
	}
	if subjectName == "" {
		return lessonTitle + " tutorial for beginners"
	}
	return fmt.Sprintf("%s %s educational video tutorial", subjectName, lessonTitle)
}

// GenerateQueryVariants returns a few alternative phrasings, useful if the
// primary query returns zero results and you want a fallback retry.
func GenerateQueryVariants(lessonTitle, subjectName string) []string {
	variants := []string{
		fmt.Sprintf("%s for beginners", lessonTitle),
		fmt.Sprintf("%s tutorial", lessonTitle),
	}
	if subjectName != "" {
		variants = append(variants, fmt.Sprintf("%s %s class", subjectName, lessonTitle))
	}
	return variants
}

'@
New-FileUtf8NoBom -Path $p_backend_internal_youtube_search_generator_go -Content $content_p_backend_internal_youtube_search_generator_go

$p_backend_internal_youtube_repository_go = Join-Path $root 'backend\internal\youtube\repository.go'
$content_p_backend_internal_youtube_repository_go = @'
package youtube

import (
	"context"
	"database/sql"
	"encoding/json"
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
// Adjust the JOIN/column names below to match your existing lessons/subjects
// tables if they differ.
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
	_, err := r.db.ExecContext(ctx, q, query, lessonID)
	return err
}

// GetCachedVideos returns a non-expired cache entry for lessonID+query, if any.
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

// SaveCache stores fresh results with a 24h TTL.
func (r *Repository) SaveCache(ctx context.Context, lessonID int64, query string, videos []YoutubeVideo) error {
	raw, err := json.Marshal(videos)
	if err != nil {
		return err
	}
	const q = `
		INSERT INTO youtube_cache (lesson_id, query, response_json, created_at, expires_at)
		VALUES ($1, $2, $3, now(), $4)`
	_, err = r.db.ExecContext(ctx, q, lessonID, query, raw, time.Now().Add(24*time.Hour))
	return err
}

// UpsertProgress records/updates how much of a video a user has watched.
func (r *Repository) UpsertProgress(ctx context.Context, userID, lessonID int64, req VideoProgressRequest) error {
	const q = `
		INSERT INTO lesson_video_progress (user_id, lesson_id, video_id, watched_seconds, completed, updated_at)
		VALUES ($1, $2, $3, $4, $5, now())
		ON CONFLICT (user_id, lesson_id, video_id)
		DO UPDATE SET watched_seconds = EXCLUDED.watched_seconds,
		              completed = EXCLUDED.completed,
		              updated_at = now()`
	_, err := r.db.ExecContext(ctx, q, userID, lessonID, req.VideoID, req.WatchedSeconds, req.Completed)
	return err
}

'@
New-FileUtf8NoBom -Path $p_backend_internal_youtube_repository_go -Content $content_p_backend_internal_youtube_repository_go

$p_backend_internal_youtube_service_go = Join-Path $root 'backend\internal\youtube\service.go'
$content_p_backend_internal_youtube_service_go = @'
package youtube

import (
	"context"
	"log"
)

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
func (s *Service) SearchVideos(ctx context.Context, q string) ([]YoutubeVideo, error) {
	return s.client.Search(ctx, q)
}

// RecordProgress saves a user's watch progress for a video within a lesson.
func (s *Service) RecordProgress(ctx context.Context, userID, lessonID int64, req VideoProgressRequest) error {
	return s.repo.UpsertProgress(ctx, userID, lessonID, req)
}

'@
New-FileUtf8NoBom -Path $p_backend_internal_youtube_service_go -Content $content_p_backend_internal_youtube_service_go

$p_backend_internal_youtube_handler_go = Join-Path $root 'backend\internal\youtube\handler.go'
$content_p_backend_internal_youtube_handler_go = @'
package youtube

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// RegisterRoutes wires this package's endpoints into an existing Gin router
// group. Call this from your main router setup, e.g.:
//
//	youtubeHandler := youtube.NewHandler(youtubeService)
//	youtubeHandler.RegisterRoutes(api, authMiddleware)
//
// authMiddleware should be your existing JWT middleware — this package does
// not implement or modify auth.
func (h *Handler) RegisterRoutes(router gin.IRouter, authMiddleware gin.HandlerFunc) {
	lessons := router.Group("/lessons")
	lessons.Use(authMiddleware)
	{
		lessons.GET("/:id/videos", h.GetLessonVideos)
		lessons.POST("/:id/videos/progress", h.SaveVideoProgress)
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch videos", "details": err.Error()})
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, videos)
}

// SaveVideoProgress handles POST /api/lessons/:id/videos/progress
// Expects the authenticated user id to be set on the context by your
// existing auth middleware under the key "userID" (adjust if your
// middleware uses a different key).
func (h *Handler) SaveVideoProgress(c *gin.Context) {
	lessonID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid lesson id"})
		return
	}

	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthenticated"})
		return
	}
	userID, ok := userIDVal.(int64)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid user id in context"})
		return
	}

	var req VideoProgressRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payload", "details": err.Error()})
		return
	}

	if err := h.service.RecordProgress(c.Request.Context(), userID, lessonID, req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save progress", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

'@
New-FileUtf8NoBom -Path $p_backend_internal_youtube_handler_go -Content $content_p_backend_internal_youtube_handler_go

$p_flutter_models_youtube_video_dart = Join-Path $root 'flutter\models\youtube_video.dart'
$content_p_flutter_models_youtube_video_dart = @'
class YoutubeVideo {
  final String videoId;
  final String title;
  final String? description;
  final String thumbnail;
  final String channel;
  final String? publishedAt;
  final String duration;

  YoutubeVideo({
    required this.videoId,
    required this.title,
    this.description,
    required this.thumbnail,
    required this.channel,
    this.publishedAt,
    required this.duration,
  });

  factory YoutubeVideo.fromJson(Map<String, dynamic> json) {
    return YoutubeVideo(
      videoId: json['video_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      thumbnail: json['thumbnail'] ?? '',
      channel: json['channel'] ?? '',
      publishedAt: json['published_at'],
      duration: json['duration'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'video_id': videoId,
      'title': title,
      'description': description,
      'thumbnail': thumbnail,
      'channel': channel,
      'published_at': publishedAt,
      'duration': duration,
    };
  }
}

'@
New-FileUtf8NoBom -Path $p_flutter_models_youtube_video_dart -Content $content_p_flutter_models_youtube_video_dart

$p_flutter_services_youtube_service_dart = Join-Path $root 'flutter\services\youtube_service.dart'
$content_p_flutter_services_youtube_service_dart = @'
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/youtube_video.dart';

/// Talks to the Go backend's /api/lessons/:id/videos and
/// /api/videos/search endpoints.
///
/// TODO: replace [baseUrl] and the auth header logic below with your
/// existing ApiConstants / AuthService pattern (same one used by
/// api_service.dart elsewhere in the app) so the token stays in sync.
class YoutubeService {
  final String baseUrl;
  final String? Function() getAuthToken;

  YoutubeService({
    required this.baseUrl,
    required this.getAuthToken,
  });

  Map<String, String> get _headers {
    final token = getAuthToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/lessons/:id/videos
  Future<List<YoutubeVideo>> getLessonVideos(int lessonId) async {
    final uri = Uri.parse('$baseUrl/api/lessons/$lessonId/videos');
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => YoutubeVideo.fromJson(json)).toList();
    }
    throw YoutubeServiceException(
      'Failed to load videos (status ${response.statusCode})',
      response.statusCode,
    );
  }

  /// GET /api/videos/search?q=
  Future<List<YoutubeVideo>> searchVideos(String query) async {
    final uri = Uri.parse('$baseUrl/api/videos/search')
        .replace(queryParameters: {'q': query});
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => YoutubeVideo.fromJson(json)).toList();
    }
    throw YoutubeServiceException(
      'Search failed (status ${response.statusCode})',
      response.statusCode,
    );
  }

  /// POST /api/lessons/:id/videos/progress
  Future<void> saveProgress({
    required int lessonId,
    required String videoId,
    required int watchedSeconds,
    required bool completed,
  }) async {
    final uri = Uri.parse('$baseUrl/api/lessons/$lessonId/videos/progress');
    final response = await http
        .post(
          uri,
          headers: _headers,
          body: jsonEncode({
            'video_id': videoId,
            'watched_seconds': watchedSeconds,
            'completed': completed,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw YoutubeServiceException(
        'Failed to save progress (status ${response.statusCode})',
        response.statusCode,
      );
    }
  }
}

class YoutubeServiceException implements Exception {
  final String message;
  final int? statusCode;
  YoutubeServiceException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

'@
New-FileUtf8NoBom -Path $p_flutter_services_youtube_service_dart -Content $content_p_flutter_services_youtube_service_dart

$p_flutter_providers_youtube_provider_dart = Join-Path $root 'flutter\providers\youtube_provider.dart'
$content_p_flutter_providers_youtube_provider_dart = @'
import 'package:flutter/foundation.dart';
import '../models/youtube_video.dart';
import '../services/youtube_service.dart';

enum YoutubeLoadStatus { idle, loading, loaded, empty, error }

/// Uses ChangeNotifier (package:provider) to match the rest of the app's
/// state pattern. If your app uses Riverpod instead, wrap this class's
/// logic in a StateNotifier — the method bodies stay the same.
class YoutubeProvider extends ChangeNotifier {
  final YoutubeService _service;

  YoutubeProvider(this._service);

  YoutubeLoadStatus status = YoutubeLoadStatus.idle;
  List<YoutubeVideo> videos = [];
  String? errorMessage;
  int? _currentLessonId;

  Future<void> loadVideosForLesson(int lessonId) async {
    _currentLessonId = lessonId;
    status = YoutubeLoadStatus.loading;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _service.getLessonVideos(lessonId);
      videos = result;
      status = result.isEmpty ? YoutubeLoadStatus.empty : YoutubeLoadStatus.loaded;
    } on YoutubeServiceException catch (e) {
      status = YoutubeLoadStatus.error;
      errorMessage = e.message;
    } catch (e) {
      status = YoutubeLoadStatus.error;
      errorMessage = 'Something went wrong. Please check your connection.';
    }
    notifyListeners();
  }

  Future<void> retry() async {
    if (_currentLessonId != null) {
      await loadVideosForLesson(_currentLessonId!);
    }
  }

  Future<void> recordProgress({
    required String videoId,
    required int watchedSeconds,
    required bool completed,
  }) async {
    if (_currentLessonId == null) return;
    try {
      await _service.saveProgress(
        lessonId: _currentLessonId!,
        videoId: videoId,
        watchedSeconds: watchedSeconds,
        completed: completed,
      );
    } catch (e) {
      // Progress save failures shouldn't block video playback UX.
      debugPrint('youtube_provider: failed to save progress: $e');
    }
  }
}

'@
New-FileUtf8NoBom -Path $p_flutter_providers_youtube_provider_dart -Content $content_p_flutter_providers_youtube_provider_dart

$p_flutter_widgets_video_card_dart = Join-Path $root 'flutter\widgets\video_card.dart'
$content_p_flutter_widgets_video_card_dart = @'
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/youtube_video.dart';

/// Pastel-styled video card matching the AI Tutor app's visual language.
/// Adjust the color constants below if your app centralizes theme colors
/// elsewhere (e.g. AppColors / AppTheme).
class VideoCard extends StatelessWidget {
  final YoutubeVideo video;
  final VoidCallback onWatch;
  final int index;

  const VideoCard({
    super.key,
    required this.video,
    required this.onWatch,
    this.index = 0,
  });

  static const _cardColor = Color(0xFFFDF6F0); // pastel cream
  static const _accentColor = Color(0xFFB8A6E8); // pastel lavender
  static const _textDark = Color(0xFF3A3153);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: _cardColor,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _accentColor.withOpacity(0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onWatch,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      video.thumbnail,
                      width: 120,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 120,
                        height: 80,
                        color: _accentColor.withOpacity(0.15),
                        child: const Icon(Icons.play_circle_outline, color: _textDark),
                      ),
                    ),
                  ),
                  if (video.duration.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          video.duration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      video.channel,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: _textDark.withOpacity(0.65),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: onWatch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text(
                          'Watch',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 80).ms, duration: 300.ms).slideY(begin: 0.08, end: 0);
  }
}

'@
New-FileUtf8NoBom -Path $p_flutter_widgets_video_card_dart -Content $content_p_flutter_widgets_video_card_dart

$p_flutter_screens_lesson_videos_screen_dart = Join-Path $root 'flutter\screens\lesson_videos_screen.dart'
$content_p_flutter_screens_lesson_videos_screen_dart = @'
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../models/youtube_video.dart';
import '../providers/youtube_provider.dart';
import '../widgets/video_card.dart';

/// Drop this screen/widget in between "AI Explanation" and "PDF Notes"
/// in your existing lesson detail flow. It does not alter AI Explanation,
/// PDF Notes, or Mark Complete — those stay exactly as they are.
class LessonVideosScreen extends StatefulWidget {
  final int lessonId;
  final String lessonTitle;

  const LessonVideosScreen({
    super.key,
    required this.lessonId,
    required this.lessonTitle,
  });

  @override
  State<LessonVideosScreen> createState() => _LessonVideosScreenState();
}

class _LessonVideosScreenState extends State<LessonVideosScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<YoutubeProvider>().loadVideosForLesson(widget.lessonId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<YoutubeProvider>(
      builder: (context, provider, _) {
        switch (provider.status) {
          case YoutubeLoadStatus.idle:
          case YoutubeLoadStatus.loading:
            return _buildSkeleton();
          case YoutubeLoadStatus.error:
            return _buildError(provider);
          case YoutubeLoadStatus.empty:
            return _buildEmpty();
          case YoutubeLoadStatus.loaded:
            return _buildVideoList(context, provider.videos);
        }
      },
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Shimmer(
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(YoutubeProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 36, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            provider.errorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => provider.retry(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'No educational videos found.',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text('Continue learning with:', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
          Text('✓ AI Explanation', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
          Text('✓ PDF Notes', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
          Text('✓ Practice Questions', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildVideoList(BuildContext context, List<YoutubeVideo> videos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recommended Videos',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...videos.asMap().entries.map(
              (entry) => VideoCard(
                video: entry.value,
                index: entry.key,
                onWatch: () => _openPlayer(context, entry.value),
              ),
            ),
      ],
    );
  }

  void _openPlayer(BuildContext context, YoutubeVideo video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          video: video,
          onProgress: (seconds, completed) {
            context.read<YoutubeProvider>().recordProgress(
                  videoId: video.videoId,
                  watchedSeconds: seconds,
                  completed: completed,
                );
          },
        ),
      ),
    );
  }
}

/// Full player screen: play/pause/seek/fullscreen/landscape via
/// youtube_player_iframe.
class VideoPlayerScreen extends StatefulWidget {
  final YoutubeVideo video;
  final void Function(int watchedSeconds, bool completed) onProgress;

  const VideoPlayerScreen({
    super.key,
    required this.video,
    required this.onProgress,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.video.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        enableCaption: true,
      ),
    );

    _controller.listen((event) {
      final seconds = event.position.inSeconds;
      final completed = event.playerState == PlayerState.ended;
      widget.onProgress(seconds, completed);
    });
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.video.title, overflow: TextOverflow.ellipsis)),
      body: YoutubePlayerScaffold(
        controller: _controller,
        aspectRatio: 16 / 9,
        builder: (context, player) {
          return Column(
            children: [
              player,
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.video.title,
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(widget.video.channel,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Minimal shimmer effect with no external dependency. Swap for your
/// existing shimmer widget/package if the app already has one.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + (0.5 * (1 - (_controller.value - 0.5).abs() * 2)),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

'@
New-FileUtf8NoBom -Path $p_flutter_screens_lesson_videos_screen_dart -Content $content_p_flutter_screens_lesson_videos_screen_dart

$p_migrations_006_add_youtube_integration_sql = Join-Path $root 'migrations\006_add_youtube_integration.sql'
$content_p_migrations_006_add_youtube_integration_sql = @'
-- Migration: Add YouTube video integration
-- Safe to run on existing DB. Does NOT touch auth, categories, subjects, notes,
-- search, progress-tracking, or ai_tutor tables.

BEGIN;

-- 1. Extend lessons table
ALTER TABLE lessons
    ADD COLUMN IF NOT EXISTS youtube_search_query TEXT,
    ADD COLUMN IF NOT EXISTS youtube_enabled BOOLEAN DEFAULT true;

-- 2. Cache table (24h TTL, keyed by lesson_id + query)
CREATE TABLE IF NOT EXISTS youtube_cache (
    id            BIGSERIAL PRIMARY KEY,
    lesson_id     BIGINT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
    query         TEXT NOT NULL,
    response_json JSONB NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_youtube_cache_lesson_id ON youtube_cache(lesson_id);
CREATE INDEX IF NOT EXISTS idx_youtube_cache_expires_at ON youtube_cache(expires_at);

-- 3. Per-user, per-video watch progress
CREATE TABLE IF NOT EXISTS lesson_video_progress (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lesson_id       BIGINT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
    video_id        TEXT NOT NULL,
    watched_seconds INTEGER NOT NULL DEFAULT 0,
    completed       BOOLEAN NOT NULL DEFAULT false,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, lesson_id, video_id)
);

CREATE INDEX IF NOT EXISTS idx_lesson_video_progress_user_lesson
    ON lesson_video_progress(user_id, lesson_id);

COMMIT;

'@
New-FileUtf8NoBom -Path $p_migrations_006_add_youtube_integration_sql -Content $content_p_migrations_006_add_youtube_integration_sql

Write-Host "`nDone. Project created at: $root"