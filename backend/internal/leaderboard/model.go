package leaderboard

const (
	PeriodWeekly  = "weekly"
	PeriodMonthly = "monthly"
	PeriodOverall = "overall"
)

// Entry is one row on the leaderboard.
type Entry struct {
	Rank          int    `json:"rank"`
	StudentID     int    `json:"student_id"`
	StudentName   string `json:"student_name"`
	Class         string `json:"class,omitempty"`
	Section       string `json:"section,omitempty"`
	TotalXP       int    `json:"total_xp"`
	TotalPoints   int    `json:"total_points"`
	IsCurrentUser bool   `json:"is_current_user"`
}
