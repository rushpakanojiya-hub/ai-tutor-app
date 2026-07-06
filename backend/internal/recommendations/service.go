package recommendations

// Service contains the business logic for recommendations.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a recommendations Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// GetForUser recomputes and returns a user's current recommendations.
func (s *Service) GetForUser(userID int) ([]Recommendation, error) {
	return s.repo.ComputeAndStore(userID)
}
