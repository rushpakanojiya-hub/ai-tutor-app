package subjects

import "errors"

var ErrNoLessonsYet = errors.New("at least one lesson is required before publishing")

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

// --- Admin Course Management ---

func (s *Service) AdminList(search string, categoryID *int, status *string) ([]AdminCourseSummary, error) {
	return s.repo.AdminList(search, categoryID, status)
}

func (s *Service) Update(id int, req UpdateCourseRequest) error {
	if req.Name != nil && *req.Name == "" {
		return errors.New("course name is required")
	}
	return s.repo.Update(id, req)
}

func (s *Service) Delete(id int) error {
	return s.repo.Delete(id)
}

// Publish enforces "at least one lesson required before publishing".
func (s *Service) Publish(id int) error {
	count, err := s.repo.CountLessons(id)
	if err != nil {
		return err
	}
	if count < 1 {
		return ErrNoLessonsYet
	}
	return s.repo.SetStatus(id, StatusPublished)
}

func (s *Service) Unpublish(id int) error {
	return s.repo.SetStatus(id, StatusDraft)
}
