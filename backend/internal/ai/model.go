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
