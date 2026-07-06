// Package recommendations implements simple, rule-based "what to learn
// next" suggestions â€” NOT a machine-learning model. The rule is: for each
// subject where the student has completed lessons, recommend the next
// not-yet-completed lesson in that subject (by order_number). This mirrors
// the spec's examples (completed Mathematics Introduction + Algebra ->
// recommend Geometry) using the existing lessons.order_number column
// instead of a hardcoded lesson-to-lesson map.
package recommendations

import "time"

// Recommendation mirrors a "recommendations" table row, with the
// recommended lesson's title/subject joined in for direct display.
type Recommendation struct {
	ID                   int       `json:"id"`
	UserID               int       `json:"user_id"`
	LessonID             int       `json:"lesson_id"`
	RecommendedLessonID  int       `json:"recommended_lesson_id"`
	RecommendedTitle     string    `json:"recommended_title"`
	RecommendedSubjectID int       `json:"recommended_subject_id"`
	SubjectName          string    `json:"subject_name"`
	CreatedAt            time.Time `json:"created_at"`
}
