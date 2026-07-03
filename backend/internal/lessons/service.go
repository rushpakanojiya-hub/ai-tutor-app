package lessons

import "errors"

// Service contains the business logic for lessons.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a lessons Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ListBySubject returns every lesson for a subject, in display order.
func (s *Service) ListBySubject(subjectID int) ([]Lesson, error) {
	return s.repo.FindBySubjectID(subjectID)
}

// GetByID returns a single lesson by ID.
func (s *Service) GetByID(id int) (*Lesson, error) {
	return s.repo.FindByID(id)
}

// Create validates and inserts a new lesson.
func (s *Service) Create(req CreateLessonRequest) (int, error) {
	if req.Title == "" {
		return 0, errors.New("lesson title is required")
	}
	if req.SubjectID <= 0 {
		return 0, errors.New("a valid subject_id is required")
	}
	return s.repo.Create(req)
}