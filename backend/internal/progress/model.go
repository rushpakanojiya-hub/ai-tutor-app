// Package progress tracks which lessons each user has completed
// (lesson_progress table) and derives per-subject completion percentages.
package progress

import "time"

// LessonProgress mirrors a "lesson_progress" table row.
type LessonProgress struct {
	ID          int       `json:"id"`
	UserID      int       `json:"user_id"`
	LessonID    int       `json:"lesson_id"`
	CompletedAt time.Time `json:"completed_at"`
}

// SubjectProgress is the aggregated view returned to the Flutter app:
// how many of a subject's lessons the current user has completed, and
// which specific lesson IDs â€” so the Lessons screen can render checkmarks
// without a separate call per lesson.
type SubjectProgress struct {
	SubjectID           int     `json:"subject_id"`
	TotalLessons        int     `json:"total_lessons"`
	CompletedLessons    int     `json:"completed_lessons"`
	Percentage          float64 `json:"percentage"` // 0.0 - 1.0
	CompletedLessonIDs  []int   `json:"completed_lesson_ids"`
}
