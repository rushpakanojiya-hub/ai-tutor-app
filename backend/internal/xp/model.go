package xp

const (
	ActivityQuizCompletion    = "quiz_completion"
	ActivityHomeworkSubmit    = "homework_submission"
	ActivityCourseCompletion  = "course_completion"
	ActivityDailyStudy        = "daily_study"
	ActivityStudyStreak       = "study_streak"
)

// Award amounts - flat and simple for this first pass (no
// difficulty/score scaling yet).
const (
	XPQuizCompletion   = 20
	PointsQuizCompletion = 10

	XPHomeworkSubmit   = 30
	PointsHomeworkSubmit = 15

	XPCourseCompletion   = 100
	PointsCourseCompletion = 50

	XPDailyStudy   = 10
	PointsDailyStudy = 5

	XPStudyStreak   = 50
	PointsStudyStreak = 25
)

// xpPerLevel defines the level curve - flat 100 XP per level for this
// first pass (no exponential scaling yet).
const xpPerLevel = 100

// Summary is the response for GET /api/xp/mine - everything the
// dashboard's XP progress bar needs.
type Summary struct {
	TotalXP          int     `json:"total_xp"`
	TotalPoints      int     `json:"total_points"`
	Level            int     `json:"level"`
	XPIntoLevel      int     `json:"xp_into_level"`
	XPToNextLevel    int     `json:"xp_to_next_level"`
	ProgressFraction float64 `json:"progress_fraction"` // 0.0-1.0, for a progress bar
}

func summaryFromTotals(totalXP, totalPoints int) Summary {
	level := totalXP/xpPerLevel + 1
	xpIntoLevel := totalXP % xpPerLevel
	return Summary{
		TotalXP:          totalXP,
		TotalPoints:      totalPoints,
		Level:            level,
		XPIntoLevel:      xpIntoLevel,
		XPToNextLevel:    xpPerLevel - xpIntoLevel,
		ProgressFraction: float64(xpIntoLevel) / float64(xpPerLevel),
	}
}
