package streak

// Service exposes streak computation. RecordActivity is called by other
// packages (progress, quiz, ai) whenever the student does something -
// this package doesn't know or care which action, it just marks the day.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) RecordActivity(userID int) error {
	return s.repo.RecordActivity(userID)
}

// HeatmapDay is one cell in the learning calendar heatmap.
type HeatmapDay struct {
	Date   string `json:"date"`
	Active bool   `json:"active"`
}

// Summary is the full response for GET /api/streak.
type Summary struct {
	CurrentStreak      int          `json:"current_streak"`
	LongestStreak      int          `json:"longest_streak"`
	ActiveDaysThisWeek int          `json:"active_days_this_week"`
	WeeklyActivity     []bool       `json:"weekly_activity"`
	Heatmap            []HeatmapDay `json:"heatmap"`
}

func (s *Service) GetSummary(userID int) (*Summary, error) {
	currentStreak, err := s.repo.GetCurrentStreak(userID)
	if err != nil {
		return nil, err
	}
	longestStreak, err := s.repo.GetLongestStreak(userID)
	if err != nil {
		return nil, err
	}
	weekCount, err := s.repo.GetActiveDaysThisWeek(userID)
	if err != nil {
		return nil, err
	}
	weeklyActivity, err := s.repo.GetWeeklyActivity(userID)
	if err != nil {
		return nil, err
	}
	heatmap, err := s.repo.GetActivityHeatmap(userID, 35)
	if err != nil {
		return nil, err
	}

	return &Summary{
		CurrentStreak:      currentStreak,
		LongestStreak:      longestStreak,
		ActiveDaysThisWeek: weekCount,
		WeeklyActivity:     weeklyActivity,
		Heatmap:            heatmap,
	}, nil
}

// --- Learning Calendar month view (additive) ---

// MonthCalendar is the response for GET /api/streak/calendar.
type MonthCalendar struct {
	Year        int      `json:"year"`
	Month       int      `json:"month"`
	ActiveDates []string `json:"active_dates"`
}

func (s *Service) GetMonthCalendar(userID, year, month int) (*MonthCalendar, error) {
	dates, err := s.repo.GetActiveDatesForMonth(userID, year, month)
	if err != nil {
		return nil, err
	}
	return &MonthCalendar{Year: year, Month: month, ActiveDates: dates}, nil
}