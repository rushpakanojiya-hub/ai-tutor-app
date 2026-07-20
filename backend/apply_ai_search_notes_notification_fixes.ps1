# apply_ai_search_notes_notification_fixes.ps1
# Run from your backend project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\backend)
# Writes: ai module (best-effort persistence + rows.Err fixes), search module (query
# trim/cap), notes + notification modules (info-leak + RowsAffected fixes), and
# rows.Err()/rows.Close() fixes in categories/subjects/lessons/aicontent search methods.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying ai/search/notes/notification fixes in $root" -ForegroundColor Cyan

# --- internal/ai/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/ai") | Out-Null
$content_internal_ai_repository_go = @'
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
//
// BUG FIX: was missing a rows.Err() check after the scan loop.
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
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// DeleteSession removes a session (and its messages, via ON DELETE CASCADE).
//
// BUG FIX: didn't check RowsAffected - deleting someone else's session id
// (or a nonexistent one) matched 0 rows but still reported success to the
// caller, silently doing nothing instead of surfacing "not found".
func (r *Repository) DeleteSession(userID, sessionID int) error {
	res, err := r.db.Exec(`DELETE FROM ai_chat_sessions WHERE id = $1 AND user_id = $2`, sessionID, userID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrSessionNotFound
	}
	return nil
}

// AddMessage inserts a message into a session.
func (r *Repository) AddMessage(sessionID int, role, message string) (int, error) {
	var id int
	query := `INSERT INTO ai_chat_messages (session_id, role, message) VALUES ($1, $2, $3) RETURNING id`
	err := r.db.QueryRow(query, sessionID, role, message).Scan(&id)
	return id, err
}

// ListMessages returns every message in a session, oldest first.
//
// BUG FIX: was missing a rows.Err() check after the scan loop.
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
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// RecentMessages returns up to limit of the most recent messages in a
// session, oldest-first - used to build the context window sent to Groq
// ("load last 10 messages"). Call this BEFORE saving the current turn's
// user message, so the returned history doesn't include it yet.
//
// BUG FIX: was missing a rows.Err() check after the scan loop - a
// connection error mid-iteration would silently truncate the context
// window sent to Groq instead of surfacing as an error, which could make
// the AI Tutor "forget" earlier turns without any error being reported.
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
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// QA fix ("Roll back failed AI messages"): added so the Service can undo
// a saved user message if the Groq call that was supposed to follow it
// fails - without this, there was no way to remove the now-orphaned
// message and the conversation was left inconsistent (a question with
// no reply, permanently).
func (r *Repository) DeleteMessage(messageID int) error {
	_, err := r.db.Exec(`DELETE FROM ai_chat_messages WHERE id = $1`, messageID)
	return err
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/ai/repository.go"), $content_internal_ai_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/ai/repository.go" -ForegroundColor Green

# --- internal/ai/service.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/ai") | Out-Null
$content_internal_ai_service_go = @'
package ai

import (
	"context"
	"errors"
	"log"

	"ai-tutor-backend/internal/streak"
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
	streakSvc    *streak.Service
}

// NewService wires a Repository, the subjects Repository (for subject-name
// lookups used in the prompt), a GroqClient, and the shared streak Service
// into an ai Service.
func NewService(repo *Repository, subjectsRepo *subjects.Repository, groqClient *GroqClient, streakSvc *streak.Service) *Service {
	return &Service{repo: repo, subjectsRepo: subjectsRepo, groqClient: groqClient, streakSvc: streakSvc}
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

	title := truncateTitle(req.Message, 50)
	return s.repo.CreateSession(userID, req.SubjectID, title)
}

// truncateTitle cuts a session title to at most maxRunes RUNES (not
// bytes) - QA fix ("UTF-8 title truncation"): the previous version did
// title[:50], a BYTE slice. For Hindi/Marathi messages (which this app
// explicitly supports), a multi-byte UTF-8 character sitting right at
// that boundary got sliced in half, producing a mangled/invalid title.
func truncateTitle(message string, maxRunes int) string {
	runes := []rune(message)
	if len(runes) <= maxRunes {
		return message
	}
	return string(runes[:maxRunes]) + "..."
}

// subjectName resolves a subject_id into its display name for the system
// prompt (e.g. "Mathematics") - returns "" if none was given or it can't
// be found, so a chat without a subject still works normally.
func (s *Service) subjectName(subjectID *int) string {
	if subjectID == nil {
		return ""
	}
	subject, err := s.subjectsRepo.FindByID(0, *subjectID)
	if err != nil {
		return ""
	}
	return subject.Name
}

// Chat handles one turn: resolves/creates the session, loads the last 10
// messages as context, sends everything to Groq, saves both the
// student's message and the AI's reply, and returns the reply.
//
// QA fix ("Roll back failed AI messages" / "Preserve chat consistency"):
// the student's message used to be saved to the DB BEFORE calling Groq,
// with no cleanup if that call then failed. If Groq fails, the just-saved
// user message is deleted so the session's history stays consistent.
//
// BUG FIX (this pass): after a SUCCESSFUL (and billed) Groq call, saving
// the assistant's reply (AddMessage) or touching the session
// (TouchSession) could still fail on a transient DB hiccup - and the
// previous code treated that as a hard failure, returning an error and
// discarding the reply entirely. The student would see "something went
// wrong" despite the AI Tutor having already generated a perfectly good
// answer (that Groq call cost real money). These two persistence steps
// are now best-effort: failures are logged, but the reply is still
// returned to the caller either way. Worst case, that one reply doesn't
// appear in the session's history on reload - much better than losing it
// outright.
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

	userMessageID, err := s.repo.AddMessage(sessionID, "user", req.Message)
	if err != nil {
		return nil, err
	}

	subjectName := s.subjectName(req.SubjectID)
	messages := buildMessages(subjectName, req.Language, req.Mode, history, req.Message)

	reply, err := s.groqClient.Chat(ctx, messages)
	if err != nil {
		if rollbackErr := s.repo.DeleteMessage(userMessageID); rollbackErr != nil {
			log.Printf("[ai] failed to roll back orphaned user message %d after Groq error: %v", userMessageID, rollbackErr)
		}
		if errors.Is(err, ErrNoAPIKey) {
			return nil, ErrAINotConfigured
		}
		return nil, err
	}

	if _, err := s.repo.AddMessage(sessionID, "assistant", reply); err != nil {
		log.Printf("[ai] failed to persist assistant reply for session %d (reply still returned to caller): %v", sessionID, err)
	}
	if err := s.repo.TouchSession(sessionID); err != nil {
		log.Printf("[ai] failed to touch session %d after reply (non-fatal): %v", sessionID, err)
	}
	_ = s.streakSvc.RecordActivity(userID) // best-effort

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
[System.IO.File]::WriteAllText((Join-Path $root "internal/ai/service.go"), $content_internal_ai_service_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/ai/service.go" -ForegroundColor Green

# --- internal/ai/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/ai") | Out-Null
$content_internal_ai_handler_go = @'
package ai

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/pkg/logger"
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
		logger.Error("ai: request failed", err)
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
		logger.Error("ai: ListSessions failed", err)
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
//
// BUG FIX: previously always returned a generic 500 on any error,
// including when the session simply didn't exist/belong to the caller
// (now that Service/Repository correctly return ErrSessionNotFound for
// that case - see repository.go). Routed through respondAIError so that
// maps to a proper 404, consistent with every other endpoint in this
// package.
func (h *Handler) DeleteSession(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid session id")
		return
	}

	userID := c.GetInt("user_id")

	if err := h.service.DeleteSession(userID, id); err != nil {
		h.respondAIError(c, err)
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Session deleted", nil)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/ai/handler.go"), $content_internal_ai_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/ai/handler.go" -ForegroundColor Green

# --- internal/search/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/search") | Out-Null
$content_internal_search_handler_go = @'
package search

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// maxQueryLen caps how long a search term can be before it's sent to the
// DB - a pure defensive bound (four unbounded ILIKE '%...%' queries run
// per search), not a real-world search term length.
const maxQueryLen = 200

// Handler adapts HTTP requests/responses to the search Service.
type Handler struct {
	service *Service
}

// NewHandler builds a search Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// Search handles GET /api/search?q=math.
//
// BUG FIX: the query was passed straight through un-trimmed and
// unbounded - a whitespace-only "q" (e.g. "   ") isn't caught by the
// ErrEmptyQuery check (since it isn't literally "") and used to run four
// pointless ILIKE queries against every table; an arbitrarily long "q"
// had no upper bound either.
func (h *Handler) Search(c *gin.Context) {
	query := strings.TrimSpace(c.Query("q"))
	if len(query) > maxQueryLen {
		query = query[:maxQueryLen]
	}

	results, err := h.service.Search(query)
	if err != nil {
		if errors.Is(err, ErrEmptyQuery) {
			utils.RespondError(c, http.StatusBadRequest, "Query parameter 'q' is required")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Search failed")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Search results", results)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/search/handler.go"), $content_internal_search_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/search/handler.go" -ForegroundColor Green

# --- internal/notes/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/notes") | Out-Null
$content_internal_notes_repository_go = @'
package notes

import "database/sql"

// Repository handles direct SQL access for notes.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a notes Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// FindByLessonID returns every note attached to a lesson.
//
// BUG FIX: was missing a rows.Err() check after the scan loop.
func (r *Repository) FindByLessonID(lessonID int) ([]Note, error) {
	query := `SELECT id, lesson_id, title, pdf_url, created_at FROM notes WHERE lesson_id = $1 ORDER BY id`
	rows, err := r.db.Query(query, lessonID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.ID, &n.LessonID, &n.Title, &n.PDFURL, &n.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, n)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// Create inserts a new note and returns its generated ID.
func (r *Repository) Create(lessonID int, title, pdfURL string) (int, error) {
	var id int
	query := `INSERT INTO notes (lesson_id, title, pdf_url) VALUES ($1, $2, $3) RETURNING id`
	err := r.db.QueryRow(query, lessonID, title, pdfURL).Scan(&id)
	return id, err
}

// --- Lesson Resource Management (additive) ---
//
// The admin/teacher "PDF Notes" upload in Lesson Resource Management
// needs to show up in the existing student-facing notes list (the
// NotesWidget reads from this same "notes" table via ListByLesson), so
// these let the lessons package keep exactly one note in sync with a
// lesson's pdf_url without duplicating the notes UI/table.

// FindFirstByLessonID returns the first note for a lesson, or nil if none.
func (r *Repository) FindFirstByLessonID(lessonID int) (*Note, error) {
	var n Note
	query := `SELECT id, lesson_id, title, pdf_url, created_at FROM notes WHERE lesson_id = $1 ORDER BY id LIMIT 1`
	err := r.db.QueryRow(query, lessonID).Scan(&n.ID, &n.LessonID, &n.Title, &n.PDFURL, &n.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &n, nil
}

func (r *Repository) Update(id int, title, pdfURL string) error {
	res, err := r.db.Exec(`UPDATE notes SET title = $1, pdf_url = $2 WHERE id = $3`, title, pdfURL, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrNoteNotFound
	}
	return nil
}

func (r *Repository) Delete(id int) error {
	res, err := r.db.Exec(`DELETE FROM notes WHERE id = $1`, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrNoteNotFound
	}
	return nil
}

// FindByID returns a single note by id, or ErrNoteNotFound if none.
func (r *Repository) FindByID(id int) (*Note, error) {
	var n Note
	query := `SELECT id, lesson_id, title, pdf_url, created_at FROM notes WHERE id = $1`
	err := r.db.QueryRow(query, id).Scan(&n.ID, &n.LessonID, &n.Title, &n.PDFURL, &n.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrNoteNotFound
	}
	if err != nil {
		return nil, err
	}
	return &n, nil
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/notes/repository.go"), $content_internal_notes_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/notes/repository.go" -ForegroundColor Green

# --- internal/notes/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/notes") | Out-Null
$content_internal_notes_handler_go = @'
package notes

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/pkg/logger"
	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the notes Service.
type Handler struct {
	service *Service
}

// NewHandler builds a notes Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// requireTeacherOrAdmin mirrors lessons.requireTeacherOrAdmin - PDF
// notes are managed from inside the Lesson page by the same roles that
// manage the lesson itself.
func requireTeacherOrAdmin(c *gin.Context) bool {
	role := c.GetString("role")
	if role != "admin" && role != "teacher" {
		utils.RespondError(c, http.StatusForbidden, "Only teachers and admins can manage notes")
		return false
	}
	return true
}

// isValidationError reports whether err is one of the plain input-
// validation errors Service.Create returns directly - these only ever
// describe the client's own input and are safe to show verbatim.
// Anything else (e.g. a foreign-key violation because lesson_id doesn't
// exist) is a real DB error and must not be echoed to the client.
func isValidationError(err error) bool {
	switch err.Error() {
	case "title and pdf_url are required", "a valid lesson_id is required":
		return true
	default:
		return false
	}
}

// ListByLesson handles GET /api/lessons/:id/notes.
func (h *Handler) ListByLesson(c *gin.Context) {
	lessonID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	list, err := h.service.ListByLesson(lessonID)
	if err != nil {
		logger.Error("notes: ListByLesson failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load notes")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Notes fetched", list)
}

// Create handles POST /api/notes (teacher or admin).
//
// QA fix: previously had no role check - any authenticated user could
// create a note.
//
// BUG FIX (info leak): a DB error (e.g. lesson_id referencing a lesson
// that doesn't exist -> foreign-key violation) used to be sent to the
// client verbatim via err.Error(). Only known-safe validation messages
// are shown now; anything else is logged server-side.
func (h *Handler) Create(c *gin.Context) {
	if !requireTeacherOrAdmin(c) {
		return
	}
	var req CreateNoteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "lesson_id, title, and pdf_url are required")
		return
	}
	id, err := h.service.Create(req)
	if err != nil {
		if isValidationError(err) {
			utils.RespondError(c, http.StatusBadRequest, err.Error())
			return
		}
		logger.Error("notes: Create failed", err)
		utils.RespondError(c, http.StatusBadRequest, "Could not create note - check that the lesson exists")
		return
	}
	utils.RespondSuccess(c, http.StatusCreated, "Note created", gin.H{"id": id})
}

// --- Lesson Resource Management (additive) ---

// Update handles PUT /api/notes/:id (teacher or admin) - "Replace PDF"
// and editing PDF title/description.
//
// BUG FIX (info leak): same reasoning as Create above.
func (h *Handler) Update(c *gin.Context) {
	if !requireTeacherOrAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid note id")
		return
	}
	var req UpdateNoteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	if err := h.service.Update(id, req); err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Note not found")
			return
		}
		logger.Error("notes: Update failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update note")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Note updated", nil)
}

// Delete handles DELETE /api/notes/:id (teacher or admin) - "Remove PDF".
func (h *Handler) Delete(c *gin.Context) {
	if !requireTeacherOrAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid note id")
		return
	}
	if err := h.service.Delete(id); err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Note not found")
			return
		}
		logger.Error("notes: Delete failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to delete note")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Note deleted", nil)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/notes/handler.go"), $content_internal_notes_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/notes/handler.go" -ForegroundColor Green

# --- internal/notification/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/notification") | Out-Null
$content_internal_notification_repository_go = @'
package notification

import (
	"database/sql"
	"errors"
)

// ErrNotificationNotFound is returned when a notification id doesn't
// exist, or doesn't belong to the requesting user.
var ErrNotificationNotFound = errors.New("notification not found")

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// Create inserts one notification for one user.
func (r *Repository) Create(userID int, notifType, title, body string, relatedID int) error {
	_, err := r.db.Exec(`
		INSERT INTO notifications (user_id, type, title, body, related_id)
		VALUES ($1, $2, $3, $4, $5)`,
		userID, notifType, title, body, relatedID,
	)
	return err
}

// CreateForUsers fans the same notification out to many users at once
// (e.g. every student, when a new live class is scheduled).
func (r *Repository) CreateForUsers(userIDs []int, notifType, title, body string, relatedID int) error {
	if len(userIDs) == 0 {
		return nil
	}
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, uid := range userIDs {
		if _, err := tx.Exec(`
			INSERT INTO notifications (user_id, type, title, body, related_id)
			VALUES ($1, $2, $3, $4, $5)`,
			uid, notifType, title, body, relatedID,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// AllStudentIDs is a small helper used to fan a notification out to
// every student - there's no per-class enrollment/registration in this
// app, so "every student" is the honest audience for "a new class was
// scheduled".
func (r *Repository) AllStudentIDs() ([]int, error) {
	rows, err := r.db.Query(`SELECT id FROM users WHERE role = 'student'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (r *Repository) ListForUser(userID int) ([]Notification, error) {
	rows, err := r.db.Query(`
		SELECT id, type, title, body, related_id, is_read, created_at
		FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Notification
	for rows.Next() {
		var n Notification
		if err := rows.Scan(&n.ID, &n.Type, &n.Title, &n.Body, &n.RelatedID, &n.IsRead, &n.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, n)
	}
	return result, rows.Err()
}

func (r *Repository) CountUnread(userID int) (int, error) {
	var count int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = false`, userID).Scan(&count)
	return count, err
}

// MarkRead marks one notification as read, scoped to userID so a user
// can't mark (or even discover the existence of) someone else's
// notification by guessing an id.
//
// BUG FIX: didn't check RowsAffected - marking a nonexistent id, or one
// belonging to a different user, matched 0 rows but still reported
// success ("Marked as read") to the caller instead of surfacing that
// nothing actually happened.
func (r *Repository) MarkRead(id, userID int) error {
	res, err := r.db.Exec(`UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotificationNotFound
	}
	return nil
}

// MarkAllRead marks every unread notification as read. 0 rows affected
// is a legitimate outcome here (nothing was unread) rather than an
// error, unlike MarkRead above which targets one specific id.
func (r *Repository) MarkAllRead(userID int) error {
	_, err := r.db.Exec(`UPDATE notifications SET is_read = true WHERE user_id = $1 AND is_read = false`, userID)
	return err
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/notification/repository.go"), $content_internal_notification_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/notification/repository.go" -ForegroundColor Green

# --- internal/notification/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/notification") | Out-Null
$content_internal_notification_handler_go = @'
package notification

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/pkg/logger"
	"ai-tutor-backend/utils"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) List(c *gin.Context) {
	userID := c.GetInt("user_id")
	list, err := h.service.ListForUser(userID)
	if err != nil {
		logger.Error("notification: List failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load notifications")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Notifications fetched", list)
}

func (h *Handler) UnreadCount(c *gin.Context) {
	userID := c.GetInt("user_id")
	count, err := h.service.CountUnread(userID)
	if err != nil {
		logger.Error("notification: UnreadCount failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to count notifications")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Count fetched", gin.H{"unread_count": count})
}

// BUG FIX: now that Repository.MarkRead reports ErrNotificationNotFound
// for a nonexistent/not-yours id (see repository.go), map it to a proper
// 404 instead of falling into the previous behavior of either a generic
// 500 or a false-positive 200.
func (h *Handler) MarkRead(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid notification id")
		return
	}
	userID := c.GetInt("user_id")
	if err := h.service.MarkRead(id, userID); err != nil {
		if errors.Is(err, ErrNotificationNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Notification not found")
			return
		}
		logger.Error("notification: MarkRead failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update notification")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Marked as read", nil)
}

func (h *Handler) MarkAllRead(c *gin.Context) {
	userID := c.GetInt("user_id")
	if err := h.service.MarkAllRead(userID); err != nil {
		logger.Error("notification: MarkAllRead failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update notifications")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "All marked as read", nil)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/notification/handler.go"), $content_internal_notification_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/notification/handler.go" -ForegroundColor Green

# --- internal/categories/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/categories") | Out-Null
$content_internal_categories_repository_go = @'
package categories

import (
	"database/sql"
	"errors"
)

// ErrCategoryNotFound is returned when no category matches the given ID.
var ErrCategoryNotFound = errors.New("category not found")

// Repository handles direct SQL access for course_categories.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a categories Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// FindAll returns every category, ordered by name for a stable grid layout.
func (r *Repository) FindAll() ([]Category, error) {
	rows, err := r.db.Query(`SELECT id, name, icon, created_at FROM course_categories ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []Category
	for rows.Next() {
		var c Category
		var icon sql.NullString
		if err := rows.Scan(&c.ID, &c.Name, &icon, &c.CreatedAt); err != nil {
			return nil, err
		}
		c.Icon = icon.String
		result = append(result, c)
	}
	return result, nil
}

// FindByID returns a single category, or ErrCategoryNotFound.
func (r *Repository) FindByID(id int) (*Category, error) {
	query := `SELECT id, name, icon, created_at FROM course_categories WHERE id = $1`
	var c Category
	var icon sql.NullString
	err := r.db.QueryRow(query, id).Scan(&c.ID, &c.Name, &icon, &c.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrCategoryNotFound
	}
	if err != nil {
		return nil, err
	}
	c.Icon = icon.String
	return &c, nil
}

// Create inserts a new category and returns its generated ID.
func (r *Repository) Create(name, icon string) (int, error) {
	var id int
	query := `INSERT INTO course_categories (name, icon) VALUES ($1, $2) RETURNING id`
	err := r.db.QueryRow(query, name, icon).Scan(&id)
	return id, err
}

// SearchByName does a case-insensitive partial match, used by the global
// search endpoint (Feature 6).
func (r *Repository) SearchByName(query string) ([]Category, error) {
	rows, err := r.db.Query(
		`SELECT id, name, icon, created_at FROM course_categories WHERE name ILIKE '%' || $1 || '%' ORDER BY name`,
		query,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []Category
	for rows.Next() {
		var c Category
		var icon sql.NullString
		if err := rows.Scan(&c.ID, &c.Name, &icon, &c.CreatedAt); err != nil {
			return nil, err
		}
		c.Icon = icon.String
		result = append(result, c)
	}
	// BUG FIX: was missing a rows.Err() check - a connection error mid-
	// iteration would silently truncate search results instead of
	// surfacing as an error.
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// Update applies only the provided (non-nil) fields - part of Course
// Categories management.
func (r *Repository) Update(id int, req UpdateCategoryRequest) error {
	res, err := r.db.Exec(`
		UPDATE course_categories SET
			name = COALESCE($1, name),
			icon = COALESCE($2, icon)
		WHERE id = $3`,
		req.Name, req.Icon, id,
	)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrCategoryNotFound
	}
	return nil
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/categories/repository.go"), $content_internal_categories_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/categories/repository.go" -ForegroundColor Green

# --- internal/subjects/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/subjects") | Out-Null
$content_internal_subjects_repository_go = @'
package subjects

import (
	"database/sql"
	"errors"
	"strconv"
)

// ErrSubjectNotFound is returned when no subject matches the given ID.
var ErrSubjectNotFound = errors.New("subject not found")

// Repository handles direct SQL access for subjects.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a subjects Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// baseSelect uses scalar subqueries (not joins) for each count/sum so rows
// are never multiplied - each subquery independently counts against its
// own table. userID drives the ProgressPercentage subquery; pass 0 for
// contexts with no signed-in user (progress will just read 0%).
const baseSelect = `
	SELECT
		s.id, s.category_id, s.name, s.description, s.thumbnail, s.difficulty, s.created_at,
		(SELECT COUNT(*) FROM lessons l WHERE l.subject_id = s.id) AS lesson_count,
		(SELECT COUNT(*) FROM notes n JOIN lessons l ON l.id = n.lesson_id WHERE l.subject_id = s.id) AS notes_count,
		(SELECT COUNT(*) FROM lesson_ai_content ac JOIN lessons l ON l.id = ac.lesson_id
			WHERE l.subject_id = s.id AND ac.quiz_json IS NOT NULL AND ac.quiz_json::text <> '[]') AS quiz_count,
		(SELECT COALESCE(SUM(l.duration), 0) FROM lessons l WHERE l.subject_id = s.id) AS total_duration_minutes,
		(SELECT COALESCE(SUM(l.duration), 0) FROM lessons l JOIN lesson_progress lp ON lp.lesson_id = l.id AND lp.user_id = $1
			WHERE l.subject_id = s.id) AS completed_duration_minutes,
		(SELECT COUNT(*) FROM lessons l WHERE l.subject_id = s.id) AS total_for_progress,
		(SELECT COUNT(*) FROM lessons l JOIN lesson_progress lp ON lp.lesson_id = l.id AND lp.user_id = $1
			WHERE l.subject_id = s.id) AS completed_for_progress
	FROM subjects s
`

func scanSubject(row interface{ Scan(...any) error }) (Subject, error) {
	var s Subject
	var description, thumbnail sql.NullString
	var totalDurationMinutes, completedDurationMinutes, totalForProgress, completedForProgress int

	err := row.Scan(
		&s.ID, &s.CategoryID, &s.Name, &description, &thumbnail, &s.Difficulty, &s.CreatedAt,
		&s.LessonCount, &s.NotesCount, &s.QuizCount,
		&totalDurationMinutes, &completedDurationMinutes, &totalForProgress, &completedForProgress,
	)
	s.Description = description.String
	s.Thumbnail = thumbnail.String
	s.LearningHours = float64(totalDurationMinutes) / 60.0
	s.CompletedHours = float64(completedDurationMinutes) / 60.0
	s.CompletedLessons = completedForProgress

	if totalForProgress > 0 {
		s.ProgressPercentage = (float64(completedForProgress) / float64(totalForProgress)) * 100
	}

	return s, err
}

// FindAll returns every subject across all categories, with progress
// computed for userID (pass 0 if there's no signed-in user in context).
func (r *Repository) FindAll(userID int) ([]Subject, error) {
	query := baseSelect + ` GROUP BY s.id ORDER BY s.name`
	rows, err := r.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Subject
	for rows.Next() {
		s, err := scanSubject(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	return result, nil
}

// FindByCategoryID returns every subject belonging to one category.
func (r *Repository) FindByCategoryID(userID, categoryID int) ([]Subject, error) {
	query := baseSelect + ` WHERE s.category_id = $2 GROUP BY s.id ORDER BY s.name`
	rows, err := r.db.Query(query, userID, categoryID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Subject
	for rows.Next() {
		s, err := scanSubject(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	return result, nil
}

// FindByID returns a single subject, or ErrSubjectNotFound.
func (r *Repository) FindByID(userID, id int) (*Subject, error) {
	query := baseSelect + ` WHERE s.id = $2 GROUP BY s.id`
	row := r.db.QueryRow(query, userID, id)
	s, err := scanSubject(row)
	if err == sql.ErrNoRows {
		return nil, ErrSubjectNotFound
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// Create inserts a new subject and returns its generated ID.
func (r *Repository) Create(categoryID int, name, description, thumbnail string) (int, error) {
	var id int
	query := `
		INSERT INTO subjects (category_id, name, description, thumbnail)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`
	err := r.db.QueryRow(query, categoryID, name, description, thumbnail).Scan(&id)
	return id, err
}

// SearchByName does a case-insensitive partial match, used by the global
// search endpoint (Feature 6).
func (r *Repository) SearchByName(userID int, query string) ([]Subject, error) {
	sqlQuery := baseSelect + ` WHERE s.name ILIKE '%' || $2 || '%' GROUP BY s.id ORDER BY s.name`
	rows, err := r.db.Query(sqlQuery, userID, query)
	if err != nil {
		return nil, err
	}
	// BUG FIX: rows.Close() was missing entirely (not just rows.Err()) -
	// every call to SearchByName leaked a DB connection/statement handle,
	// since nothing ever released it back to the pool.
	defer rows.Close()

	var result []Subject
	for rows.Next() {
		s, err := scanSubject(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// --- Admin Course Management (additive) ---

var ErrCourseNotFound = errors.New("course not found")

// AdminList powers the Course Management screen - search + filter by
// category/status, with the exact fields the course cards need
// (thumbnail, lesson/enrollment counts, status) - a deliberately
// separate query from baseSelect above, so nothing student-facing is
// touched by these filters.
func (r *Repository) AdminList(search string, categoryID *int, status *string) ([]AdminCourseSummary, error) {
	query := `
		SELECT s.id, s.name, COALESCE(s.description, ''), COALESCE(s.thumbnail, ''), s.difficulty, s.status,
		       s.category_id, cc.name,
		       (SELECT COUNT(*) FROM lessons l WHERE l.subject_id = s.id) AS total_lessons,
		       (SELECT COUNT(*) FROM subject_enrollments se WHERE se.subject_id = s.id) AS enrolled_count
		FROM subjects s
		JOIN course_categories cc ON cc.id = s.category_id
		WHERE 1=1
	`
	args := []interface{}{}
	argN := 1

	if search != "" {
		query += ` AND s.name ILIKE '%' || $` + strconv.Itoa(argN) + ` || '%'`
		args = append(args, search)
		argN++
	}
	if categoryID != nil {
		query += ` AND s.category_id = $` + strconv.Itoa(argN)
		args = append(args, *categoryID)
		argN++
	}
	if status != nil && *status != "" {
		query += ` AND s.status = $` + strconv.Itoa(argN)
		args = append(args, *status)
		argN++
	}
	query += ` ORDER BY s.name`

	rows, err := r.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []AdminCourseSummary
	for rows.Next() {
		var c AdminCourseSummary
		if err := rows.Scan(&c.ID, &c.Name, &c.Description, &c.Thumbnail, &c.Difficulty, &c.Status,
			&c.CategoryID, &c.CategoryName, &c.TotalLessons, &c.EnrolledCount); err != nil {
			return nil, err
		}
		result = append(result, c)
	}
	return result, rows.Err()
}

// Update applies only the provided (non-nil) fields.
func (r *Repository) Update(id int, req UpdateCourseRequest) error {
	_, err := r.db.Exec(`
		UPDATE subjects SET
			category_id = COALESCE($1, category_id),
			name = COALESCE($2, name),
			description = COALESCE($3, description),
			thumbnail = COALESCE($4, thumbnail),
			difficulty = COALESCE($5, difficulty)
		WHERE id = $6`,
		req.CategoryID, req.Name, req.Description, req.Thumbnail, req.Difficulty, id,
	)
	return err
}

// Delete removes the course (subject) - lessons/enrollments cascade via
// existing FK constraints (ON DELETE CASCADE), unchanged from before.
func (r *Repository) Delete(id int) error {
	res, err := r.db.Exec(`DELETE FROM subjects WHERE id = $1`, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrCourseNotFound
	}
	return nil
}

// SetStatus - used by Publish/Unpublish.
func (r *Repository) SetStatus(id int, status string) error {
	res, err := r.db.Exec(`UPDATE subjects SET status = $1 WHERE id = $2`, status, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrCourseNotFound
	}
	return nil
}

// CountLessons - used to enforce "at least one lesson required before
// publishing".
func (r *Repository) CountLessons(subjectID int) (int, error) {
	var count int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons WHERE subject_id = $1`, subjectID).Scan(&count)
	return count, err
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/subjects/repository.go"), $content_internal_subjects_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/subjects/repository.go" -ForegroundColor Green

# --- internal/lessons/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/lessons") | Out-Null
$content_internal_lessons_repository_go = @'
package lessons

import (
	"database/sql"
	"errors"
)

// ErrLessonNotFound is returned when no lesson matches the given ID.
var ErrLessonNotFound = errors.New("lesson not found")

// Repository handles direct SQL access for lessons.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a lessons Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

const selectColumns = `id, subject_id, title, description, video_url, video_source, pdf_url, pdf_title, pdf_description, assignment_url, thumbnail_url, duration, order_number, status, created_at`

func scanLesson(row interface{ Scan(...any) error }) (Lesson, error) {
	var l Lesson
	var description, videoURL, videoSource, pdfURL, pdfTitle, pdfDescription, assignmentURL, thumbnailURL sql.NullString
	err := row.Scan(&l.ID, &l.SubjectID, &l.Title, &description, &videoURL, &videoSource, &pdfURL, &pdfTitle, &pdfDescription, &assignmentURL, &thumbnailURL, &l.Duration, &l.OrderNumber, &l.Status, &l.CreatedAt)
	l.Description = description.String
	l.VideoURL = videoURL.String
	l.VideoSource = videoSource.String
	l.PDFURL = pdfURL.String
	l.PDFTitle = pdfTitle.String
	l.PDFDescription = pdfDescription.String
	l.AssignmentURL = assignmentURL.String
	l.ThumbnailURL = thumbnailURL.String
	return l, err
}

// FindBySubjectID returns every lesson for a subject, in display order.
func (r *Repository) FindBySubjectID(subjectID int) ([]Lesson, error) {
	query := `SELECT ` + selectColumns + ` FROM lessons WHERE subject_id = $1 ORDER BY order_number, id`
	rows, err := r.db.Query(query, subjectID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Lesson
	for rows.Next() {
		l, err := scanLesson(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, l)
	}
	return result, nil
}

// FindByID returns a single lesson, or ErrLessonNotFound.
func (r *Repository) FindByID(id int) (*Lesson, error) {
	query := `SELECT ` + selectColumns + ` FROM lessons WHERE id = $1`
	row := r.db.QueryRow(query, id)
	l, err := scanLesson(row)
	if err == sql.ErrNoRows {
		return nil, ErrLessonNotFound
	}
	if err != nil {
		return nil, err
	}
	return &l, nil
}

// Create inserts a new lesson and returns its generated ID.
func (r *Repository) Create(req CreateLessonRequest) (int, error) {
	var id int
	query := `
		INSERT INTO lessons (subject_id, title, description, video_url, pdf_url, thumbnail_url, duration, order_number)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id
	`
	err := r.db.QueryRow(
		query,
		req.SubjectID, req.Title, req.Description, req.VideoURL, req.PDFURL, req.ThumbnailURL, req.Duration, req.OrderNumber,
	).Scan(&id)
	return id, err
}

// SearchByTitle does a case-insensitive partial match, used by the global
// search endpoint (Feature 6).
func (r *Repository) SearchByTitle(query string) ([]Lesson, error) {
	sqlQuery := `SELECT ` + selectColumns + ` FROM lessons WHERE title ILIKE '%' || $1 || '%' ORDER BY title`
	rows, err := r.db.Query(sqlQuery, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Lesson
	for rows.Next() {
		l, err := scanLesson(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, l)
	}
	// BUG FIX: was missing a rows.Err() check - a connection error mid-
	// iteration would silently truncate search results instead of
	// surfacing as an error.
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// --- Admin Course Management (additive) ---

// Update applies only the provided (non-nil) fields.
func (r *Repository) Update(id int, req UpdateLessonRequest) error {
	res, err := r.db.Exec(`
		UPDATE lessons SET
			title = COALESCE($1, title),
			description = COALESCE($2, description),
			video_url = COALESCE($3, video_url),
			video_source = COALESCE($4, video_source),
			pdf_url = COALESCE($5, pdf_url),
			pdf_title = COALESCE($6, pdf_title),
			pdf_description = COALESCE($7, pdf_description),
			thumbnail_url = COALESCE($8, thumbnail_url),
			duration = COALESCE($9, duration)
		WHERE id = $10`,
		req.Title, req.Description, req.VideoURL, req.VideoSource, req.PDFURL, req.PDFTitle, req.PDFDescription, req.ThumbnailURL, req.Duration, id,
	)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrLessonNotFound
	}
	return nil
}

// Delete removes the lesson - lesson_progress/notes/etc cascade via
// existing FK constraints, unchanged from before.
func (r *Repository) Delete(id int) error {
	res, err := r.db.Exec(`DELETE FROM lessons WHERE id = $1`, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrLessonNotFound
	}
	return nil
}

// Reorder updates order_number for a batch of lessons in one transaction -
// powers drag-and-drop reordering.
func (r *Repository) Reorder(items []ReorderItem) error {
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, item := range items {
		if _, err := tx.Exec(`UPDATE lessons SET order_number = $1 WHERE id = $2`, item.OrderNumber, item.ID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (r *Repository) SetVideoURL(id int, url string) error {
	// Direct file uploads always set video_source back to "upload" -
	// this is what distinguishes an uploaded file from a pasted
	// YouTube URL (set via Update) when the player decides how to
	// render the lesson's video.
	_, err := r.db.Exec(`UPDATE lessons SET video_url = $1, video_source = 'upload' WHERE id = $2`, url, id)
	return err
}

func (r *Repository) SetPDFURL(id int, url string) error {
	_, err := r.db.Exec(`UPDATE lessons SET pdf_url = $1 WHERE id = $2`, url, id)
	return err
}

func (r *Repository) SetAssignmentURL(id int, url string) error {
	_, err := r.db.Exec(`UPDATE lessons SET assignment_url = $1 WHERE id = $2`, url, id)
	return err
}

// --- Lesson Resource Management (additive) ---

// SetStatus - used by Publish/Unpublish, same pattern as subjects.SetStatus.
func (r *Repository) SetStatus(id int, status string) error {
	res, err := r.db.Exec(`UPDATE lessons SET status = $1 WHERE id = $2`, status, id)
	if err != nil {
		return err
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		return ErrLessonNotFound
	}
	return nil
}
'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/lessons/repository.go"), $content_internal_lessons_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/lessons/repository.go" -ForegroundColor Green

# --- internal/aicontent/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/aicontent") | Out-Null
$content_internal_aicontent_repository_go = @'
package aicontent

import (
	"database/sql"
	"errors"
)

// ErrNotFound is returned when a lesson has no AI content generated yet.
var ErrNotFound = errors.New("ai content not found for this lesson")

// Repository handles direct SQL access for lesson_ai_content.
type Repository struct {
	db *sql.DB
}

// NewRepository builds an aicontent Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

const selectColumns = `id, lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json, generated_at`

// FindByLessonID returns the AI content for a lesson, or ErrNotFound if
// none has been generated for it (older lessons may not have any yet â€”
// the Flutter side shows "AI content not available yet" in that case
// rather than an error).
func (r *Repository) FindByLessonID(lessonID int) (*AIContent, error) {
	query := `SELECT ` + selectColumns + ` FROM lesson_ai_content WHERE lesson_id = $1`

	var raw rawAIContent
	err := r.db.QueryRow(query, lessonID).Scan(
		&raw.ID, &raw.LessonID, &raw.Explanation, &raw.Summary,
		&raw.KeyPoints, &raw.Examples, &raw.PracticeQuestions, &raw.QuizJSON, &raw.GeneratedAt,
	)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return raw.toAIContent()
}

// SearchByText does a case-insensitive partial match against explanation
// and summary, returning the matching lesson_ids â€” used by the global
// search endpoint (Feature 6, extended per this request to search AI content).
func (r *Repository) SearchByText(query string) ([]int, error) {
	rows, err := r.db.Query(
		`SELECT lesson_id FROM lesson_ai_content WHERE explanation ILIKE '%' || $1 || '%' OR summary ILIKE '%' || $1 || '%'`,
		query,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	// BUG FIX: was missing a rows.Err() check - a connection error mid-
	// iteration would silently truncate search results instead of
	// surfacing as an error.
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return ids, nil
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/aicontent/repository.go"), $content_internal_aicontent_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/aicontent/repository.go" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Yellow
Write-Host "  1. go build ./... to sanity check"
Write-Host "  2. cd .. ; docker compose build --no-cache backend"
Write-Host "  3. docker compose up -d --force-recreate backend"
Write-Host "  4. docker logs ai_tutor_backend --tail 15"