package notes

import "errors"

// Service contains the business logic for notes.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a notes Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ListByLesson returns every note attached to a lesson.
func (s *Service) ListByLesson(lessonID int) ([]Note, error) {
	return s.repo.FindByLessonID(lessonID)
}

// Create validates and inserts a new note.
func (s *Service) Create(req CreateNoteRequest) (int, error) {
	if req.Title == "" || req.PDFURL == "" {
		return 0, errors.New("title and pdf_url are required")
	}
	if req.LessonID <= 0 {
		return 0, errors.New("a valid lesson_id is required")
	}
	return s.repo.Create(req.LessonID, req.Title, req.PDFURL)
}