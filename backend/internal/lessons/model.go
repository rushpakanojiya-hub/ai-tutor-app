// Package lessons implements the third level of the hierarchy:
// each subject contains an ordered list of lessons with video + PDF content.
package lessons

import "time"

// Lesson mirrors the "lessons" table row.
type Lesson struct {
	ID              int       `json:"id"`
	SubjectID       int       `json:"subject_id"`
	Title           string    `json:"title"`
	Description     string    `json:"description"`
	VideoURL        string    `json:"video_url"`
	VideoSource     string    `json:"video_source"` // "upload" or "youtube"
	PDFURL          string    `json:"pdf_url"`
	PDFTitle        string    `json:"pdf_title"`
	PDFDescription  string    `json:"pdf_description"`
	AssignmentURL   string    `json:"assignment_url"`
	ThumbnailURL    string    `json:"thumbnail_url"`
	Duration        int       `json:"duration"` // minutes
	OrderNumber     int       `json:"order_number"`
	Status          string    `json:"status"` // "draft" or "published"
	CreatedAt       time.Time `json:"created_at"`
}

// --- Lesson Resource Management (additive) ---

const (
	StatusDraft     = "draft"
	StatusPublished = "published"
)

// CreateLessonRequest is the expected JSON body for POST /api/lessons.
type CreateLessonRequest struct {
	SubjectID    int    `json:"subject_id" binding:"required"`
	Title        string `json:"title" binding:"required"`
	Description  string `json:"description"`
	VideoURL     string `json:"video_url"`
	PDFURL       string `json:"pdf_url"`
	ThumbnailURL string `json:"thumbnail_url"`
	Duration     int    `json:"duration"`
	OrderNumber  int    `json:"order_number"`
}

// --- Admin Course Management (additive) ---

// UpdateLessonRequest - pointer fields mean "only update if present".
type UpdateLessonRequest struct {
	Title          *string `json:"title"`
	Description    *string `json:"description"`
	VideoURL       *string `json:"video_url"`
	VideoSource    *string `json:"video_source"`
	PDFURL         *string `json:"pdf_url"`
	PDFTitle       *string `json:"pdf_title"`
	PDFDescription *string `json:"pdf_description"`
	ThumbnailURL   *string `json:"thumbnail_url"`
	Duration       *int    `json:"duration"`
}

// ReorderItem pairs a lesson ID with its new order_number.
type ReorderItem struct {
	ID          int `json:"id" binding:"required"`
	OrderNumber int `json:"order_number"`
}

// ReorderLessonsRequest is the body for POST /api/subjects/:id/lessons/reorder.
type ReorderLessonsRequest struct {
	Items []ReorderItem `json:"items" binding:"required"`
}