package subjects

import "errors"

// Service contains the business logic for subjects.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a subjects Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// List returns every subject.
func (s *Service) List() ([]Subject, error) {
	return s.repo.FindAll()
}

// ListByCategory returns every subject in one category.
func (s *Service) ListByCategory(categoryID int) ([]Subject, error) {
	return s.repo.FindByCategoryID(categoryID)
}

// GetByID returns a single subject by ID.
func (s *Service) GetByID(id int) (*Subject, error) {
	return s.repo.FindByID(id)
}

// Create validates and inserts a new subject.
func (s *Service) Create(req CreateSubjectRequest) (int, error) {
	if req.Name == "" {
		return 0, errors.New("subject name is required")
	}
	if req.CategoryID <= 0 {
		return 0, errors.New("a valid category_id is required")
	}
	return s.repo.Create(req.CategoryID, req.Name, req.Description, req.Thumbnail)
}