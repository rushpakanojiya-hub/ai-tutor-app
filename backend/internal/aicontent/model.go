// Package aicontent serves AI-generated educational content (explanation,
// summary, key points, examples, practice questions, quiz) attached to a
// lesson â€” the "lesson_ai_content" table. This is generated ahead of time
// (see migration 000019 seed data) and served read-only here; there is no
// live AI/chatbot call in this package, per the "no AI chatbot, no paid
// APIs" constraint.
package aicontent

import (
	"encoding/json"
	"time"
)

// QuizQuestion is one multiple-choice question inside quiz_json.
type QuizQuestion struct {
	Question      string   `json:"question"`
	Options       []string `json:"options"`
	CorrectOption int      `json:"correct_option"` // index into Options
}

// AIContent mirrors a "lesson_ai_content" table row, with the JSONB columns
// decoded into typed Go slices instead of raw bytes.
type AIContent struct {
	ID                int            `json:"id"`
	LessonID          int            `json:"lesson_id"`
	Explanation       string         `json:"explanation"`
	Summary           string         `json:"summary"`
	KeyPoints         []string       `json:"key_points"`
	Examples          []string       `json:"examples"`
	PracticeQuestions []string       `json:"practice_questions"`
	Quiz              []QuizQuestion `json:"quiz"`
	GeneratedAt       time.Time      `json:"generated_at"`
}

// rawAIContent is the shape used only for scanning JSONB columns out of
// Postgres (as []byte) before unmarshalling them into AIContent's typed fields.
type rawAIContent struct {
	ID                int
	LessonID          int
	Explanation       string
	Summary           string
	KeyPoints         []byte
	Examples          []byte
	PracticeQuestions []byte
	QuizJSON          []byte
	GeneratedAt       time.Time
}

func (r rawAIContent) toAIContent() (*AIContent, error) {
	c := &AIContent{
		ID:          r.ID,
		LessonID:    r.LessonID,
		Explanation: r.Explanation,
		Summary:     r.Summary,
		GeneratedAt: r.GeneratedAt,
	}
	if err := json.Unmarshal(r.KeyPoints, &c.KeyPoints); err != nil {
		return nil, err
	}
	if err := json.Unmarshal(r.Examples, &c.Examples); err != nil {
		return nil, err
	}
	if err := json.Unmarshal(r.PracticeQuestions, &c.PracticeQuestions); err != nil {
		return nil, err
	}
	if err := json.Unmarshal(r.QuizJSON, &c.Quiz); err != nil {
		return nil, err
	}
	return c, nil
}
