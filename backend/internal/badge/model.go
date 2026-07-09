package badge

import "time"

// Fixed badge keys - matches the 7 rows seeded by migration 021.
const (
	KeyQuizMaster      = "quiz_master"
	KeyHomeworkHero    = "homework_hero"
	KeyStudyStreak7    = "study_streak_7"
	KeyMathChampion    = "math_champion"
	KeyPerfectScore    = "perfect_score"
	KeyCourseFinisher  = "course_finisher"
	KeyAttendanceStar  = "attendance_star"
)

type Badge struct {
	ID          int    `json:"id"`
	Key         string `json:"key"`
	Name        string `json:"name"`
	Description string `json:"description"`
	IconKey     string `json:"icon_key"`
}

// BadgeStatus is one badge shown on the "My Badges" page - includes
// earned/locked state and the earned date if applicable.
type BadgeStatus struct {
	Key         string     `json:"key"`
	Name        string     `json:"name"`
	Description string     `json:"description"`
	IconKey     string     `json:"icon_key"`
	Unlocked    bool       `json:"unlocked"`
	EarnedAt    *time.Time `json:"earned_at,omitempty"`
}
