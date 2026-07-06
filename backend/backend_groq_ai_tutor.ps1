$files = @{}
$files['main.go'] = @'
// AI Tutor Backend — Day 2 (Course & Learning Management added)
// Boots the Gin server, connects to PostgreSQL, and wires up all modules
// using Clean Architecture (handler -> service -> repository -> model).
package main

import (
	"fmt"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/database"
	"ai-tutor-backend/internal/ai"
	"ai-tutor-backend/internal/aicontent"
	"ai-tutor-backend/internal/auth"
	"ai-tutor-backend/internal/categories"
	"ai-tutor-backend/internal/lessons"
	"ai-tutor-backend/internal/middleware"
	"ai-tutor-backend/internal/notes"
	"ai-tutor-backend/internal/progress"
	"ai-tutor-backend/internal/recommendations"
	"ai-tutor-backend/internal/search"
	"ai-tutor-backend/internal/subjects"
	"ai-tutor-backend/internal/users"
	"ai-tutor-backend/pkg/logger"
)

func main() {
	cfg := configs.LoadConfig()
	gin.SetMode(cfg.GinMode)

	db := database.Connect(cfg)
	defer db.Close()

	router := gin.Default()
	router.Use(middleware.CORSMiddleware())

	// Serves lesson PDF notes from backend/static/notes/*.pdf as
	// http://<host>:<port>/static/notes/<file>.pdf — real, self-hosted
	// content instead of random third-party URLs (see migration 000014).
	router.Static("/static", "./static")

	authMiddleware := middleware.AuthMiddleware(cfg.JWTSecret)

	// --- Day 1: auth + users (unchanged) ---
	authRepo := auth.NewRepository(db)
	authService := auth.NewService(authRepo, cfg)
	authHandler := auth.NewHandler(authService)

	usersRepo := users.NewRepository(db)
	usersService := users.NewService(usersRepo)
	usersHandler := users.NewHandler(usersService)

	// --- Day 2: course & learning management ---
	categoriesRepo := categories.NewRepository(db)
	categoriesService := categories.NewService(categoriesRepo)
	categoriesHandler := categories.NewHandler(categoriesService)

	subjectsRepo := subjects.NewRepository(db)
	subjectsService := subjects.NewService(subjectsRepo)
	subjectsHandler := subjects.NewHandler(subjectsService)

	lessonsRepo := lessons.NewRepository(db)
	lessonsService := lessons.NewService(lessonsRepo)
	lessonsHandler := lessons.NewHandler(lessonsService)

	notesRepo := notes.NewRepository(db)
	notesService := notes.NewService(notesRepo)
	notesHandler := notes.NewHandler(notesService)

	progressRepo := progress.NewRepository(db)
	progressService := progress.NewService(progressRepo)
	progressHandler := progress.NewHandler(progressService)

	aiContentRepo := aicontent.NewRepository(db)
	aiContentService := aicontent.NewService(aiContentRepo)
	aiContentHandler := aicontent.NewHandler(aiContentService)

	aiRepo := ai.NewRepository(db)
	groqClient := ai.NewGroqClient(cfg.GroqAPIKey, cfg.GroqAPIURL, cfg.GroqModel)
	aiService := ai.NewService(aiRepo, subjectsRepo, groqClient)
	aiHandler := ai.NewHandler(aiService)

	recommendationsRepo := recommendations.NewRepository(db)
	recommendationsService := recommendations.NewService(recommendationsRepo)
	recommendationsHandler := recommendations.NewHandler(recommendationsService)

	// search reuses the categories/subjects/lessons/aicontent repositories directly —
	// no separate "search" table exists, it's a fan-out query.
	searchService := search.NewService(categoriesRepo, subjectsRepo, lessonsRepo, aiContentRepo)
	searchHandler := search.NewHandler(searchService)

	// --- Health checks (unchanged) ---
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
	router.GET("/api/health", func(c *gin.Context) {
		dbStatus := "connected"
		if err := db.Ping(); err != nil {
			dbStatus = "disconnected"
		}
		c.JSON(200, gin.H{
			"status":   "ok",
			"service":  "ai-tutor-backend",
			"database": dbStatus,
		})
	})

	// --- API routes ---
	api := router.Group("/api")
	authHandler.RegisterRoutes(api, authMiddleware)
	usersHandler.RegisterRoutes(api, authMiddleware)

	categories.RegisterRoutes(api, categoriesHandler, authMiddleware)
	subjects.RegisterRoutes(api, subjectsHandler, authMiddleware)
	lessons.RegisterRoutes(api, lessonsHandler, authMiddleware)
	notes.RegisterRoutes(api, notesHandler, authMiddleware)
	progress.RegisterRoutes(api, progressHandler, authMiddleware)
	aicontent.RegisterRoutes(api, aiContentHandler, authMiddleware)
	ai.RegisterRoutes(api, aiHandler, authMiddleware)
	recommendations.RegisterRoutes(api, recommendationsHandler, authMiddleware)
	search.RegisterRoutes(api, searchHandler, authMiddleware)

	// Role-gated routes are still intentionally absent (see Day 1 notes) —
	// when an admin dashboard exists, the POST endpoints above (create
	// category/subject/lesson/note) should switch to
	// middleware.RequireAdmin() instead of the plain authMiddleware.

	addr := fmt.Sprintf(":%s", cfg.Port)
	logger.Info(fmt.Sprintf("Server starting on %s (env: %s)", addr, cfg.AppEnv))
	if err := router.Run(addr); err != nil {
		logger.Error("Server failed to start", err)
	}
}

'@
$files['configs\config.go'] = @'
// Package configs loads and exposes application configuration
// read from environment variables (or a local .env file during development).
package configs

import (
	"fmt"
	"log"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

// Config holds every configurable value the app needs.
type Config struct {
	Port    string
	GinMode string
	AppEnv  string // "development", "production", etc. Informational (health check, logs).

	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	DBSSLMode  string

	// DatabaseURL, if set, takes priority over the individual DB_* fields
	// above. This is the form Docker Compose / Render / most hosts prefer
	// (a single connection string), while local dev can keep using the
	// separate DB_HOST/DB_PORT/etc. vars from Day 1 — both are supported.
	DatabaseURL string

	JWTSecret            string
	JWTAccessExpiryMin   int
	JWTRefreshExpiryDays int

	// Groq API — powers the real LLM AI Tutor (internal/ai/groq_client.go).
	GroqAPIKey string
	GroqAPIURL string
	GroqModel  string
}

// LoadConfig reads the .env file (if present) and environment variables,
// returning a populated Config. Missing values fall back to sane defaults
// so the app can still boot in development.
func LoadConfig() *Config {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, relying on system environment variables")
	}

	return &Config{
		Port:    getEnv("PORT", "8080"),
		GinMode: getEnv("GIN_MODE", "debug"),
		AppEnv:  getEnv("APP_ENV", "development"),

		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", "postgres"),
		DBPassword: getEnv("DB_PASSWORD", "root"),
		DBName:     getEnv("DB_NAME", "ai_tutor_db"),
		DBSSLMode:  getEnv("DB_SSLMODE", "disable"),

		DatabaseURL: getEnv("DATABASE_URL", ""),

		JWTSecret:            getEnv("JWT_SECRET", "insecure_dev_secret_change_me"),
		JWTAccessExpiryMin:   getEnvAsInt("JWT_ACCESS_EXPIRY_MINUTES", 60),
		JWTRefreshExpiryDays: getEnvAsInt("JWT_REFRESH_EXPIRY_DAYS", 7),

		GroqAPIKey: getEnv("GROQ_API_KEY", ""),
		GroqAPIURL: getEnv("GROQ_API_URL", "https://api.groq.com/openai/v1/chat/completions"),
		GroqModel:  getEnv("GROQ_MODEL", "llama-3.3-70b-versatile"),
	}
}

// DSN builds the PostgreSQL connection string. If DATABASE_URL is set, it is
// used as-is (Docker/production style). Otherwise it's assembled from the
// individual DB_* fields, exactly as Day 1 did.
func (c *Config) DSN() string {
	if c.DatabaseURL != "" {
		return c.DatabaseURL
	}
	return fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.DBHost, c.DBPort, c.DBUser, c.DBPassword, c.DBName, c.DBSSLMode,
	)
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}
	return fallback
}

func getEnvAsInt(key string, fallback int) int {
	if value, ok := os.LookupEnv(key); ok {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return fallback
}

'@
$files['.env.example'] = @'
# Server
PORT=8080
GIN_MODE=debug
APP_ENV=development

# --- Database: choose ONE of the two options below ---

# Option A (default, used by local dev without Docker): separate fields.
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=root
DB_NAME=ai_tutor_db
DB_SSLMODE=disable

# Option B (used automatically by docker-compose.yml): a single connection
# string. If DATABASE_URL is set, it overrides all DB_* fields above.
# DATABASE_URL=postgres://postgres:root@localhost:5432/ai_tutor_db?sslmode=disable

# JWT
JWT_SECRET=change_this_to_a_long_random_secret_key
JWT_ACCESS_EXPIRY_MINUTES=60
JWT_REFRESH_EXPIRY_DAYS=7

# Groq — AI Tutor's real LLM. Get a free key at https://console.groq.com
GROQ_API_KEY=
GROQ_API_URL=https://api.groq.com/openai/v1/chat/completions
GROQ_MODEL=llama-3.3-70b-versatile

'@
$files['migrations\000021_create_ai_chat_sessions_messages.up.sql'] = @'
-- Real LLM-backed AI Tutor chat (Groq API): a session belongs to a user,
-- optionally scoped to a subject, holding an ordered list of messages.
-- This replaces the earlier Day 3 rule-based ai_conversations/ai_messages
-- tables for new chats — those old tables are left in place (unused)
-- rather than dropped, so no existing data is lost.
CREATE TABLE IF NOT EXISTS ai_chat_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject_id INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_chat_messages (
    id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL REFERENCES ai_chat_sessions(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    message TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_chat_sessions_user ON ai_chat_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_session ON ai_chat_messages(session_id);

'@
$files['migrations\000021_create_ai_chat_sessions_messages.down.sql'] = @'
DROP TABLE IF EXISTS ai_chat_messages;
DROP TABLE IF EXISTS ai_chat_sessions;

'@
$files['internal\ai\model.go'] = @'
// Package ai implements the AI Tutor: a real conversational LLM (Groq's
// hosted Llama 3.3 70B, via groq_client.go) instead of static/rule-based
// responses. Conversational memory works by loading each session's recent
// message history and sending it as context on every turn (see
// prompt_builder.go), so the model itself resolves follow-up questions
// like "what are its types?" - no keyword logic is involved.
package ai

import "time"

// ChatSession mirrors an "ai_chat_sessions" table row.
type ChatSession struct {
	ID        int       `json:"id"`
	UserID    int       `json:"user_id"`
	SubjectID *int      `json:"subject_id"`
	Title     string    `json:"title"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// ChatMessage mirrors an "ai_chat_messages" table row.
type ChatMessage struct {
	ID        int       `json:"id"`
	SessionID int       `json:"session_id"`
	Role      string    `json:"role"` // "user" | "assistant" | "system"
	Message   string    `json:"message"`
	CreatedAt time.Time `json:"created_at"`
}

// SessionWithMessages is returned by GET /api/ai/sessions/:id.
type SessionWithMessages struct {
	ChatSession
	Messages []ChatMessage `json:"messages"`
}

// ChatRequest is the expected JSON body for POST /api/ai/chat.
type ChatRequest struct {
	SessionID *int   `json:"session_id"` // omit/null to start a new session
	SubjectID *int   `json:"subject_id"` // which subject this chat is scoped to (optional)
	Message   string `json:"message" binding:"required"`
	Language  string `json:"language"` // "en" (default) | "hi" | "mr"
}

// ChatResponse is returned by POST /api/ai/chat.
type ChatResponse struct {
	SessionID int    `json:"session_id"`
	Reply     string `json:"reply"`
}

'@
$files['internal\ai\repository.go'] = @'
package ai

import (
	"database/sql"
	"errors"
)

// ErrSessionNotFound is returned when a session doesn't exist or doesn't
// belong to the requesting user.
var ErrSessionNotFound = errors.New("chat session not found")

// Repository handles direct SQL access for ai_chat_sessions/ai_chat_messages.
type Repository struct {
	db *sql.DB
}

// NewRepository builds an ai Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// CreateSession inserts a new chat session and returns its ID.
func (r *Repository) CreateSession(userID int, subjectID *int, title string) (int, error) {
	var id int
	query := `INSERT INTO ai_chat_sessions (user_id, subject_id, title) VALUES ($1, $2, $3) RETURNING id`
	err := r.db.QueryRow(query, userID, subjectID, title).Scan(&id)
	return id, err
}

// TouchSession updates a session's updated_at to now.
func (r *Repository) TouchSession(sessionID int) error {
	_, err := r.db.Exec(`UPDATE ai_chat_sessions SET updated_at = NOW() WHERE id = $1`, sessionID)
	return err
}

// FindSessionByID returns a session, scoped to userID so users can't
// access each other's chat history.
func (r *Repository) FindSessionByID(userID, sessionID int) (*ChatSession, error) {
	query := `SELECT id, user_id, subject_id, title, created_at, updated_at FROM ai_chat_sessions WHERE id = $1 AND user_id = $2`
	var s ChatSession
	var subjectID sql.NullInt64
	err := r.db.QueryRow(query, sessionID, userID).Scan(&s.ID, &s.UserID, &subjectID, &s.Title, &s.CreatedAt, &s.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrSessionNotFound
	}
	if err != nil {
		return nil, err
	}
	if subjectID.Valid {
		v := int(subjectID.Int64)
		s.SubjectID = &v
	}
	return &s, nil
}

// ListSessions returns every session for a user, most recently updated first.
func (r *Repository) ListSessions(userID int) ([]ChatSession, error) {
	query := `SELECT id, user_id, subject_id, title, created_at, updated_at FROM ai_chat_sessions WHERE user_id = $1 ORDER BY updated_at DESC`
	rows, err := r.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []ChatSession
	for rows.Next() {
		var s ChatSession
		var subjectID sql.NullInt64
		if err := rows.Scan(&s.ID, &s.UserID, &subjectID, &s.Title, &s.CreatedAt, &s.UpdatedAt); err != nil {
			return nil, err
		}
		if subjectID.Valid {
			v := int(subjectID.Int64)
			s.SubjectID = &v
		}
		result = append(result, s)
	}
	return result, nil
}

// DeleteSession removes a session (and its messages, via ON DELETE CASCADE).
func (r *Repository) DeleteSession(userID, sessionID int) error {
	_, err := r.db.Exec(`DELETE FROM ai_chat_sessions WHERE id = $1 AND user_id = $2`, sessionID, userID)
	return err
}

// AddMessage inserts a message into a session.
func (r *Repository) AddMessage(sessionID int, role, message string) (int, error) {
	var id int
	query := `INSERT INTO ai_chat_messages (session_id, role, message) VALUES ($1, $2, $3) RETURNING id`
	err := r.db.QueryRow(query, sessionID, role, message).Scan(&id)
	return id, err
}

// ListMessages returns every message in a session, oldest first.
func (r *Repository) ListMessages(sessionID int) ([]ChatMessage, error) {
	query := `SELECT id, session_id, role, message, created_at FROM ai_chat_messages WHERE session_id = $1 ORDER BY id`
	rows, err := r.db.Query(query, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []ChatMessage
	for rows.Next() {
		var m ChatMessage
		if err := rows.Scan(&m.ID, &m.SessionID, &m.Role, &m.Message, &m.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, m)
	}
	return result, nil
}

// RecentMessages returns up to limit of the most recent messages in a
// session, oldest-first - used to build the context window sent to Groq
// ("load last 10 messages"). Call this BEFORE saving the current turn's
// user message, so the returned history doesn't include it yet.
func (r *Repository) RecentMessages(sessionID, limit int) ([]ChatMessage, error) {
	query := `
		SELECT id, session_id, role, message, created_at FROM (
			SELECT id, session_id, role, message, created_at
			FROM ai_chat_messages
			WHERE session_id = $1
			ORDER BY id DESC
			LIMIT $2
		) recent
		ORDER BY id ASC
	`
	rows, err := r.db.Query(query, sessionID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []ChatMessage
	for rows.Next() {
		var m ChatMessage
		if err := rows.Scan(&m.ID, &m.SessionID, &m.Role, &m.Message, &m.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, m)
	}
	return result, nil
}

'@
$files['internal\ai\service.go'] = @'
package ai

import (
	"context"
	"errors"

	"ai-tutor-backend/internal/subjects"
)

// ErrAINotConfigured is returned when GROQ_API_KEY is missing - surfaced
// as a clear "AI Tutor isn't set up yet" message rather than a raw network error.
var ErrAINotConfigured = errors.New("AI Tutor is not configured on the server")

// Service contains the business logic for AI Tutor chat: resolving/
// creating sessions, loading context, calling Groq, and persisting the
// conversation. All language generation is delegated to GroqClient -
// nothing here does keyword matching or static responses.
type Service struct {
	repo         *Repository
	subjectsRepo *subjects.Repository
	groqClient   *GroqClient
}

// NewService wires a Repository, the subjects Repository (for subject-name
// lookups used in the prompt), and a GroqClient into an ai Service.
func NewService(repo *Repository, subjectsRepo *subjects.Repository, groqClient *GroqClient) *Service {
	return &Service{repo: repo, subjectsRepo: subjectsRepo, groqClient: groqClient}
}

// resolveSession finds an existing session (verifying ownership) or
// creates a new one, returning its ID.
func (s *Service) resolveSession(userID int, req ChatRequest) (int, error) {
	if req.SessionID != nil {
		session, err := s.repo.FindSessionByID(userID, *req.SessionID)
		if err != nil {
			return 0, err
		}
		return session.ID, nil
	}

	title := req.Message
	if len(title) > 50 {
		title = title[:50] + "..."
	}
	return s.repo.CreateSession(userID, req.SubjectID, title)
}

// subjectName resolves a subject_id into its display name for the system
// prompt (e.g. "Mathematics") - returns "" if none was given or it can't
// be found, so a chat without a subject still works normally.
func (s *Service) subjectName(subjectID *int) string {
	if subjectID == nil {
		return ""
	}
	subject, err := s.subjectsRepo.FindByID(*subjectID)
	if err != nil {
		return ""
	}
	return subject.Name
}

// Chat handles one turn: resolves/creates the session, loads the last 10
// messages as context, sends everything to Groq, saves both the
// student's message and the AI's reply, and returns the reply.
func (s *Service) Chat(ctx context.Context, userID int, req ChatRequest) (*ChatResponse, error) {
	sessionID, err := s.resolveSession(userID, req)
	if err != nil {
		return nil, err
	}

	// Load history BEFORE saving the current message, so it isn't
	// double-counted when prompt_builder.go appends req.Message itself.
	history, err := s.repo.RecentMessages(sessionID, maxContextMessages)
	if err != nil {
		return nil, err
	}

	if _, err := s.repo.AddMessage(sessionID, "user", req.Message); err != nil {
		return nil, err
	}

	subjectName := s.subjectName(req.SubjectID)
	messages := buildMessages(subjectName, req.Language, history, req.Message)

	reply, err := s.groqClient.Chat(ctx, messages)
	if err != nil {
		if errors.Is(err, ErrNoAPIKey) {
			return nil, ErrAINotConfigured
		}
		return nil, err
	}

	if _, err := s.repo.AddMessage(sessionID, "assistant", reply); err != nil {
		return nil, err
	}
	if err := s.repo.TouchSession(sessionID); err != nil {
		return nil, err
	}

	return &ChatResponse{SessionID: sessionID, Reply: reply}, nil
}

// ListSessions returns a user's chat session history.
func (s *Service) ListSessions(userID int) ([]ChatSession, error) {
	return s.repo.ListSessions(userID)
}

// GetSession returns a session with all of its messages.
func (s *Service) GetSession(userID, sessionID int) (*SessionWithMessages, error) {
	session, err := s.repo.FindSessionByID(userID, sessionID)
	if err != nil {
		return nil, err
	}
	messages, err := s.repo.ListMessages(sessionID)
	if err != nil {
		return nil, err
	}
	return &SessionWithMessages{ChatSession: *session, Messages: messages}, nil
}

// DeleteSession removes a session.
func (s *Service) DeleteSession(userID, sessionID int) error {
	return s.repo.DeleteSession(userID, sessionID)
}

'@
$files['internal\ai\handler.go'] = @'
package ai

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the ai Service.
type Handler struct {
	service *Service
}

// NewHandler builds an ai Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) respondAIError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrAINotConfigured):
		utils.RespondError(c, http.StatusServiceUnavailable, "AI Tutor is not configured yet. Please contact the app admin.")
	case errors.Is(err, ErrSessionNotFound):
		utils.RespondError(c, http.StatusNotFound, "Conversation not found")
	case errors.Is(err, ErrRateLimited):
		utils.RespondError(c, http.StatusTooManyRequests, "AI Tutor is busy right now. Please try again in a moment.")
	default:
		utils.RespondError(c, http.StatusInternalServerError, "AI Tutor is having trouble responding right now. Please try again.")
	}
}

// Chat handles POST /api/ai/chat.
func (h *Handler) Chat(c *gin.Context) {
	var req ChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A message is required")
		return
	}

	userID := c.GetInt("user_id")

	resp, err := h.service.Chat(c.Request.Context(), userID, req)
	if err != nil {
		h.respondAIError(c, err)
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Reply generated", resp)
}

// ListSessions handles GET /api/ai/sessions.
func (h *Handler) ListSessions(c *gin.Context) {
	userID := c.GetInt("user_id")

	list, err := h.service.ListSessions(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load conversations")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Sessions fetched", list)
}

// GetSession handles GET /api/ai/sessions/:id.
func (h *Handler) GetSession(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid session id")
		return
	}

	userID := c.GetInt("user_id")

	session, err := h.service.GetSession(userID, id)
	if err != nil {
		h.respondAIError(c, err)
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Session fetched", session)
}

// DeleteSession handles DELETE /api/ai/sessions/:id.
func (h *Handler) DeleteSession(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid session id")
		return
	}

	userID := c.GetInt("user_id")

	if err := h.service.DeleteSession(userID, id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to delete conversation")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Session deleted", nil)
}

'@
$files['internal\ai\routes.go'] = @'
package ai

import (
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/internal/middleware"
)

// RegisterRoutes attaches all /api/ai/* chat routes. All require auth
// since chat history is scoped to the current user. Chat itself (the
// route that calls the real Groq API) is additionally rate-limited per
// user since each call has a real API cost and Groq's own limits apply.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	group := router.Group("/ai")
	group.Use(authMiddleware)

	aiRateLimit := middleware.AIRateLimitMiddleware(15, time.Minute)

	{
		group.POST("/chat", aiRateLimit, handler.Chat)
		group.GET("/sessions", handler.ListSessions)
		group.GET("/sessions/:id", handler.GetSession)
		group.DELETE("/sessions/:id", handler.DeleteSession)
	}
}

'@
$files['internal\ai\groq_client.go'] = @'
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

'@
$files['internal\ai\prompt_builder.go'] = @'
package ai

import "fmt"

// maxContextMessages caps how many recent messages are loaded from history
// and sent to Groq on each turn - per spec: "Load last 10 messages, then
// append current message, then send to Groq".
const maxContextMessages = 10

// buildSystemPrompt constructs the instruction Groq receives before any
// conversation history. This is what makes the AI Tutor subject-aware and
// language-aware, entirely replacing the old rule-based keyword matching.
func buildSystemPrompt(subjectName, language string) string {
	prompt := `You are an advanced AI Tutor.

You help students learn.

You can teach:
- Mathematics
- Science
- Physics
- Chemistry
- Biology
- History
- Geography
- English
- Programming
- Computer Science

Your responses must:
- be educational
- be beginner friendly
- explain concepts clearly
- provide examples
- provide step-by-step solutions
- support follow-up questions`

	if subjectName != "" {
		prompt += fmt.Sprintf("\n\nCurrent subject:\n%s", subjectName)
	}

	switch language {
	case "hi":
		prompt += "\n\nRespond in Hindi."
	case "mr":
		prompt += "\n\nRespond in Marathi."
	}

	return prompt
}

// buildMessages assembles the exact message list sent to Groq: the system
// prompt, then the session's recent history (oldest first), then the
// student's current message. This is where "context memory" happens - the
// LLM sees the whole recent conversation and resolves references like
// "its types" itself.
func buildMessages(subjectName, language string, history []ChatMessage, currentMessage string) []ChatCompletionMessage {
	messages := []ChatCompletionMessage{{Role: "system", Content: buildSystemPrompt(subjectName, language)}}

	for _, m := range history {
		messages = append(messages, ChatCompletionMessage{Role: m.Role, Content: m.Message})
	}

	messages = append(messages, ChatCompletionMessage{Role: "user", Content: currentMessage})

	return messages
}

'@
$files['internal\middleware\rate_limit_middleware.go'] = @'
package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// rateLimitBucket tracks one user's recent request timestamps within the
// current window — a simple in-memory sliding-window limiter. Good enough
// for a single-instance MVP backend; a multi-instance deployment would
// need a shared store (e.g. Redis) instead.
type rateLimitBucket struct {
	mu        sync.Mutex
	timestamps map[int][]time.Time
}

var aiRateLimiter = &rateLimitBucket{timestamps: make(map[int][]time.Time)}

// AIRateLimitMiddleware limits each authenticated user to maxRequests
// calls per window (e.g. 10 per minute) on AI Tutor endpoints — these are
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
		fresh := recent[:0]
		for _, t := range recent {
			if t.After(cutoff) {
				fresh = append(fresh, t)
			}
		}

		if len(fresh) >= maxRequests {
			aiRateLimiter.timestamps[userID] = fresh
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

'@

foreach ($path in $files.Keys) {
    $fullPath = Join-Path $PWD $path
    $dir = Split-Path $fullPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($fullPath, $files[$path], [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated: $path"
}
Write-Host "Backend Groq AI Tutor files applied."
Write-Host "IMPORTANT: now edit backend\.env and add your real GROQ_API_KEY (get one at https://console.groq.com/keys)"
