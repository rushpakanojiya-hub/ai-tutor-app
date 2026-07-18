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

// --- Lesson Resource Management (additive) ---

// SyncForLesson keeps a single note in step with a lesson's pdf_url -
// used by the lessons package so uploading/replacing/removing a
// lesson's PDF (in the admin/teacher Lesson Resource Management
// dialog) also updates what students see via the existing notes list,
// without either package needing to know about the other's internals.
// An empty pdfURL removes the note; a non-empty one creates or updates it.
func (s *Service) SyncForLesson(lessonID int, title, pdfURL string) error {
	existing, err := s.repo.FindFirstByLessonID(lessonID)
	if err != nil {
		return err
	}
	if pdfURL == "" {
		if existing != nil {
			return s.repo.Delete(existing.ID)
		}
		return nil
	}
	if existing != nil {
		return s.repo.Update(existing.ID, title, pdfURL)
	}
	_, err = s.repo.Create(lessonID, title, pdfURL)
	return err
}

// Update applies only the provided (non-nil) fields to a note - used
// by PUT /api/notes/:id ("Replace PDF" / edit title).
func (s *Service) Update(id int, req UpdateNoteRequest) error {
	existing, err := s.repo.FindByID(id)
	if err != nil {
		return err
	}
	title := existing.Title
	if req.Title != nil {
		title = *req.Title
	}
	pdfURL := existing.PDFURL
	if req.PDFURL != nil {
		pdfURL = *req.PDFURL
	}
	return s.repo.Update(id, title, pdfURL)
}

// Delete removes a note - used by DELETE /api/notes/:id ("Remove PDF").
func (s *Service) Delete(id int) error {
	return s.repo.Delete(id)
}