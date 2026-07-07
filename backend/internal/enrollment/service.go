package enrollment

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) EnsureEnrolled(studentID, subjectID int) error {
	return s.repo.EnsureEnrolled(studentID, subjectID)
}

func (s *Service) IsEnrolled(studentID, subjectID int) (bool, error) {
	return s.repo.IsEnrolled(studentID, subjectID)
}

func (s *Service) CountEnrolled(subjectID int) (int, error) {
	return s.repo.CountEnrolled(subjectID)
}
