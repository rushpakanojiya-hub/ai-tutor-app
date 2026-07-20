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
