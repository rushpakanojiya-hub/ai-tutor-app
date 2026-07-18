package admin

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) GetDashboardStats() (*DashboardStats, error) {
	return s.repo.GetDashboardStats()
}

// --- Student Progress Overview (additive) ---

func (s *Service) ListStudentProgress() ([]StudentProgress, error) {
	return s.repo.ListStudentProgress()
}