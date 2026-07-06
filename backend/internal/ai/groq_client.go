package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

// ErrNoAPIKey is returned when GROQ_API_KEY isn't configured - callers
// surface a clear "AI Tutor is not configured" message instead of a
// confusing network error.
var ErrNoAPIKey = errors.New("groq API key is not configured")

// ErrRateLimited is returned when Groq itself rate-limits us (HTTP 429),
// even after retries.
var ErrRateLimited = errors.New("groq API rate limit reached, please try again shortly")

// ChatCompletionMessage is one turn sent to Groq - matches the
// OpenAI-compatible chat completions "messages" array shape that Groq's
// API uses.
type ChatCompletionMessage struct {
	Role    string `json:"role"` // "system" | "user" | "assistant"
	Content string `json:"content"`
}

// GroqClient is a dedicated client for Groq's chat completions API
// (https://api.groq.com/openai/v1/chat/completions). It is the ONLY place
// in the backend that talks to Groq - Service never builds HTTP requests
// itself, keeping the LLM provider swappable and easy to mock in tests.
//
// Responsibilities: sending requests, parsing responses, timeout handling,
// a retry mechanism for transient failures, honoring Groq's own rate-limit
// responses, and basic request/error logging.
type GroqClient struct {
	apiKey     string
	apiURL     string
	model      string
	httpClient *http.Client
	maxRetries int
}

// NewGroqClient builds a GroqClient. apiURL and model fall back to Groq's
// documented defaults if empty (see configs.Config).
func NewGroqClient(apiKey, apiURL, model string) *GroqClient {
	if apiURL == "" {
		apiURL = "https://api.groq.com/openai/v1/chat/completions"
	}
	if model == "" {
		model = "llama-3.3-70b-versatile"
	}
	return &GroqClient{
		apiKey:     apiKey,
		apiURL:     apiURL,
		model:      model,
		httpClient: &http.Client{Timeout: 30 * time.Second},
		maxRetries: 2,
	}
}

type chatCompletionRequest struct {
	Model    string                   `json:"model"`
	Messages []ChatCompletionMessage `json:"messages"`
}

type chatCompletionResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}

// Chat sends the full message history (system prompt + prior turns +
// latest user message) to Groq and returns its reply as plain text.
// Retries up to maxRetries times, with a short backoff, on timeouts and
// 5xx responses; a 429 (rate limited) is retried once with a longer
// backoff and then surfaced as ErrRateLimited; 4xx errors otherwise fail
// immediately since retrying won't help.
func (c *GroqClient) Chat(ctx context.Context, messages []ChatCompletionMessage) (string, error) {
	if c.apiKey == "" {
		return "", ErrNoAPIKey
	}

	var lastErr error
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			backoff := time.Duration(attempt) * 500 * time.Millisecond
			log.Printf("[ai/groq] retrying request (attempt %d/%d) after %v: %v", attempt, c.maxRetries, backoff, lastErr)
			time.Sleep(backoff)
		}

		reply, err := c.doChat(ctx, messages)
		if err == nil {
			return reply, nil
		}
		lastErr = err

		if errors.Is(err, ErrRateLimited) {
			continue // one extra retry for rate limits specifically
		}
		var t *transientError
		if !errors.As(err, &t) {
			break // non-transient (e.g. bad request) - don't waste retries
		}
	}

	log.Printf("[ai/groq] request failed after retries: %v", lastErr)
	if errors.Is(lastErr, ErrRateLimited) {
		return "", ErrRateLimited
	}
	return "", fmt.Errorf("groq API request failed: %w", lastErr)
}

func (c *GroqClient) doChat(ctx context.Context, messages []ChatCompletionMessage) (string, error) {
	body, err := json.Marshal(chatCompletionRequest{Model: c.model, Messages: messages})
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.apiURL, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	start := time.Now()
	resp, err := c.httpClient.Do(req)
	if err != nil {
		log.Printf("[ai/groq] network error after %v: %v", time.Since(start), err)
		return "", &transientError{err}
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	log.Printf("[ai/groq] request completed in %v with status %d", time.Since(start), resp.StatusCode)

	if resp.StatusCode == http.StatusTooManyRequests {
		return "", &transientError{ErrRateLimited}
	}
	if resp.StatusCode >= 500 {
		return "", &transientError{fmt.Errorf("groq API returned status %d: %s", resp.StatusCode, string(respBody))}
	}

	var parsed chatCompletionResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return "", fmt.Errorf("failed to parse groq API response: %w", err)
	}

	if parsed.Error != nil {
		return "", fmt.Errorf("groq API error: %s", parsed.Error.Message)
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("groq API returned status %d: %s", resp.StatusCode, string(respBody))
	}
	if len(parsed.Choices) == 0 {
		return "", errors.New("groq API returned no choices")
	}

	return parsed.Choices[0].Message.Content, nil
}

// transientError marks an error as safe to retry (network/timeout/5xx/429).
type transientError struct{ err error }

func (t *transientError) Error() string { return t.err.Error() }
func (t *transientError) Unwrap() error { return t.err }
