// Package subjects implements the second level of the hierarchy:
// each course_category contains multiple subjects (e.g. Academic -> Mathematics).
package subjects

import "time"

// Subject mirrors the "subjects" table row, plus several computed,
// genuinely-backed stats for the redesigned subject card:
//   - LessonCount, NotesCount, QuizCount: real counts from their tables
//   - LearningHours: sum of lesson durations, converted to hours
//   - ProgressPercentage: the CURRENT user's completion (0-100)
//   - Difficulty: an editorial tag (Beginner/Intermediate/Advanced), not a
//     fabricated statistic
//
// Deliberately absent: a star rating and a mock-test count - neither has
// a real system behind it yet, so neither is faked here.
type Subject struct {
	ID                 int       `json:"id"`
	CategoryID         int       `json:"category_id"`
	Name               string    `json:"name"`
	Description        string    `json:"description"`
	Thumbnail          string    `json:"thumbnail"`
	Difficulty         string    `json:"difficulty"`
	LessonCount        int       `json:"lesson_count"`
	CompletedLessons   int       `json:"completed_lessons"`
	NotesCount         int       `json:"notes_count"`
	QuizCount          int       `json:"quiz_count"`
	LearningHours      float64   `json:"learning_hours"`
	ProgressPercentage float64   `json:"progress_percentage"` // 0-100, for the requesting user
	CreatedAt          time.Time `json:"created_at"`
}

// CreateSubjectRequest is the expected JSON body for POST /api/subjects.
type CreateSubjectRequest struct {
	CategoryID  int    `json:"category_id" binding:"required"`
	Name        string `json:"name" binding:"required"`
	Description string `json:"description"`
	Thumbnail   string `json:"thumbnail"`
}
