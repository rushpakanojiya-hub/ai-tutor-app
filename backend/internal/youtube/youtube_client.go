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
	// YouTube's Search API caps maxResults at 50 per request, and we
	// over-fetch at 2x this value (see the search call below) before
	// filtering/ranking - so this must never exceed 25, or the doubled
	// value sent to the API would exceed YouTube's hard limit and the
	// request would fail with a 400 error.
	if maxResults > 25 {
		maxResults = 25
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
		// Clamp to YouTube's hard API limit of 50 - if maxResults is
		// configured high enough that maxResults*2 would exceed it, the
		// API rejects the request with a 400 error instead of just
		// capping it for us.
		params.Set("maxResults", fmt.Sprintf("%d", min(c.maxResults*2, 50))) // over-fetch, then filter/rank
		params.Set("key", key)

		err := c.getWithRetry(ctx, youtubeSearchEndpoint+"?"+params.Encode(), &sr)
		if err == nil {
			break
		}

		lastErr = err
		if isQuotaError(err) {
			log.Printf("youtube: key #%d exhausted/rate-limited, rotating to next key: %v", idx, err)
			c.markBlocked(idx)
			continue
		}
		// Non-quota error (network, 5xx, etc.) â€” don't burn through all keys, just fail.
		return nil, err
	}

	if attempted == 0 {
		return nil, fmt.Errorf("youtube: all configured API keys are currently in cooldown")
	}

	if lastErr != nil && len(sr.Items) == 0 {
		return nil, fmt.Errorf("youtube: all configured keys exhausted or failed: %w", lastErr)
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
			log.Printf("youtube: duration enrichment failed (non-fatal): %v", err)
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
		if until, blocked := c.blockedUntil[idx]; blocked && time.Now().Before(until) {
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
	// process's lifetime â€” restart or next day naturally clears it.
	c.blockedUntil[idx] = time.Now().Add(6 * time.Hour)
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

		if isQuotaError(lastErr) {
			return lastErr // don't retry a quota error, let Search() rotate keys
		}

		log.Printf("youtube: attempt %d/3 failed: %v", attempt, lastErr)
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
