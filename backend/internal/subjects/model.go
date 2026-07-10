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
	CompletedHours     float64   `json:"completed_hours"`
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

// --- Admin Course Management (additive - does not touch the student-
// facing Subject/CreateSubjectRequest types or queries above) ---

const (
	StatusDraft     = "draft"
	StatusPublished = "published"
)

// AdminCourseSummary is one row on the admin's Course Management list -
// deliberately a separate, lighter type from Subject (which carries
// per-student progress fields that don't apply here).
type AdminCourseSummary struct {
	ID            int    `json:"id"`
	Name          string `json:"name"`
	Description   string `json:"description"`
	Thumbnail     string `json:"thumbnail"`
	Difficulty    string `json:"difficulty"`
	Status        string `json:"status"`
	CategoryID    int    `json:"category_id"`
	CategoryName  string `json:"category_name"`
	TotalLessons  int    `json:"total_lessons"`
	EnrolledCount int    `json:"enrolled_count"`
}

// UpdateCourseRequest - pointer fields mean "only update if present".
type UpdateCourseRequest struct {
	CategoryID  *int    `json:"category_id"`
	Name        *string `json:"name"`
	Description *string `json:"description"`
	Thumbnail   *string `json:"thumbnail"`
	Difficulty  *string `json:"difficulty"`
}
