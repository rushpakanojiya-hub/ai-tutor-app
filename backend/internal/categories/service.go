package categories

import "errors"

// Service contains the business logic for categories, independent of
// HTTP (handler.go) and SQL (repository.go) concerns.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a categories Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// List returns every category.
func (s *Service) List() ([]Category, error) {
	return s.repo.FindAll()
}

// GetByID returns a single category by ID.
func (s *Service) GetByID(id int) (*Category, error) {
	return s.repo.FindByID(id)
}

// Create validates and inserts a new category.
func (s *Service) Create(req CreateCategoryRequest) (int, error) {
	if req.Name == "" {
		return 0, errors.New("category name is required")
	}
	return s.repo.Create(req.Name, req.Icon)
}