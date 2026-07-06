package aicontent

// Service contains the business logic for AI content retrieval.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into an aicontent Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// GetByLesson returns the AI content for a lesson.
func (s *Service) GetByLesson(lessonID int) (*AIContent, error) {
	return s.repo.FindByLessonID(lessonID)
}
