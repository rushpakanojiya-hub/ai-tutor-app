// Package subjects implements the second level of the hierarchy:
// each course_category contains multiple subjects (e.g. Academic -> Mathematics).
package subjects

import "time"

// Subject mirrors the "subjects" table row, plus a computed LessonCount
// (not a DB column) so the Flutter subject card can show "12 lessons"
// without a second round-trip per subject.
type Subject struct {
	ID          int       `json:"id"`
	CategoryID  int       `json:"category_id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	Thumbnail   string    `json:"thumbnail"`
	LessonCount int       `json:"lesson_count"`
	CreatedAt   time.Time `json:"created_at"`
}

// CreateSubjectRequest is the expected JSON body for POST /api/subjects.
type CreateSubjectRequest struct {
	CategoryID  int    `json:"category_id" binding:"required"`
	Name        string `json:"name" binding:"required"`
	Description string `json:"description"`
	Thumbnail   string `json:"thumbnail"`
}