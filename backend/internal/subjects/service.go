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

// List returns every subject, with progress computed for userID.
func (s *Service) List(userID int) ([]Subject, error) {
	return s.repo.FindAll(userID)
}

// ListByCategory returns every subject in one category.
func (s *Service) ListByCategory(userID, categoryID int) ([]Subject, error) {
	return s.repo.FindByCategoryID(userID, categoryID)
}

// GetByID returns a single subject by ID.
func (s *Service) GetByID(userID, id int) (*Subject, error) {
	return s.repo.FindByID(userID, id)
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
