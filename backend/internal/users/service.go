package users

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) UpdateProfile(userID int, req UpdateProfileRequest) error {
	return s.repo.UpdateName(userID, req.Name)
}