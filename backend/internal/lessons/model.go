// Package lessons implements the third level of the hierarchy:
// each subject contains an ordered list of lessons with video + PDF content.
package lessons

import "time"

// Lesson mirrors the "lessons" table row.
type Lesson struct {
	ID          int       `json:"id"`
	SubjectID   int       `json:"subject_id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	VideoURL    string    `json:"video_url"`
	PDFURL      string    `json:"pdf_url"`
	Duration    int       `json:"duration"` // minutes
	OrderNumber int       `json:"order_number"`
	CreatedAt   time.Time `json:"created_at"`
}

// CreateLessonRequest is the expected JSON body for POST /api/lessons.
type CreateLessonRequest struct {
	SubjectID   int    `json:"subject_id" binding:"required"`
	Title       string `json:"title" binding:"required"`
	Description string `json:"description"`
	VideoURL    string `json:"video_url"`
	PDFURL      string `json:"pdf_url"`
	Duration    int    `json:"duration"`
	OrderNumber int    `json:"order_number"`
}