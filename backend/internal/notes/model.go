// Package notes implements PDF study notes attached to a lesson.
package notes

import (
	"errors"
	"time"
)

// Note mirrors the "notes" table row.
type Note struct {
	ID        int       `json:"id"`
	LessonID  int       `json:"lesson_id"`
	Title     string    `json:"title"`
	PDFURL    string    `json:"pdf_url"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateNoteRequest is the expected JSON body for POST /api/notes.
type CreateNoteRequest struct {
	LessonID int    `json:"lesson_id" binding:"required"`
	Title    string `json:"title" binding:"required"`
	PDFURL   string `json:"pdf_url" binding:"required"`
}

// --- Lesson Resource Management (additive) ---

// ErrNoteNotFound is returned by Update/Delete when the note id doesn't exist.
var ErrNoteNotFound = errors.New("note not found")

// UpdateNoteRequest - pointer fields mean "only update if present",
// same pattern as lessons.UpdateLessonRequest.
type UpdateNoteRequest struct {
	Title  *string `json:"title"`
	PDFURL *string `json:"pdf_url"`
}