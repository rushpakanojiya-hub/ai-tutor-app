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

type Summary struct {
	CurrentStreak      int `json:"current_streak"`
	ActiveDaysThisWeek int `json:"active_days_this_week"`
}

func (s *Service) GetSummary(userID int) (*Summary, error) {
	streakCount, err := s.repo.GetCurrentStreak(userID)
	if err != nil {
		return nil, err
	}
	weekCount, err := s.repo.GetActiveDaysThisWeek(userID)
	if err != nil {
		return nil, err
	}
	return &Summary{CurrentStreak: streakCount, ActiveDaysThisWeek: weekCount}, nil
}
