package lessons

import (
	"errors"
	"log"

	"ai-tutor-backend/internal/cloudinary"
)

// MaxUploadSizeBytes matches the ceiling already used for class resource
// uploads elsewhere in the app.
const MaxUploadSizeBytes = 25 * 1024 * 1024

// Service contains the business logic for lessons.
type Service struct {
	repo            *Repository
	cloudinaryClient *cloudinary.Client
}

// NewService wires a Repository and the shared Cloudinary client into a
// lessons Service.
func NewService(repo *Repository, cloudinaryClient *cloudinary.Client) *Service {
	return &Service{repo: repo, cloudinaryClient: cloudinaryClient}
}

// ListBySubject returns every lesson for a subject.
func (s *Service) ListBySubject(subjectID int) ([]Lesson, error) {
	return s.repo.FindBySubjectID(subjectID)
}

// GetByID returns a single lesson by ID.
func (s *Service) GetByID(id int) (*Lesson, error) {
	return s.repo.FindByID(id)
}

// Create validates and inserts a new lesson.
func (s *Service) Create(req CreateLessonRequest) (int, error) {
	if req.SubjectID <= 0 {
		return 0, errors.New("a valid subject_id is required")
	}
	if req.Title == "" {
		return 0, errors.New("lesson title is required")
	}
	return s.repo.Create(req)
}

// --- Admin Course Management (additive) ---

func (s *Service) Update(id int, req UpdateLessonRequest) error {
	if req.Title != nil && *req.Title == "" {
		return errors.New("lesson title is required")
	}
	return s.repo.Update(id, req)
}

func (s *Service) Delete(id int) error {
	return s.repo.Delete(id)
}

func (s *Service) Reorder(items []ReorderItem) error {
	return s.repo.Reorder(items)
}

// --- Lesson Resource Management (additive) ---

// ErrNoResourcesYet - a lesson can only be published once it has at
// least one video or PDF attached (draft is allowed without any).
var ErrNoResourcesYet = errors.New("at least one video or PDF is required before publishing")

// Publish enforces "at least one video or PDF required before publishing" -
// same shape as subjects.Service.Publish's lesson-count check.
func (s *Service) Publish(id int) error {
	lesson, err := s.repo.FindByID(id)
	if err != nil {
		return err
	}
	if lesson.VideoURL == "" && lesson.PDFURL == "" {
		return ErrNoResourcesYet
	}
	return s.repo.SetStatus(id, StatusPublished)
}

func (s *Service) Unpublish(id int) error {
	return s.repo.SetStatus(id, StatusDraft)
}

// UploadVideo, UploadPDF, UploadAssignment - same Cloudinary pattern
// already used for live-class resource uploads (internal/resource).
func (s *Service) UploadVideo(lessonID int, fileBytes []byte, filename string) (string, error) {
	result, err := s.cloudinaryClient.Upload(fileBytes, filename, "video")
	if err != nil {
		log.Printf("[lessons] Cloudinary video upload failed for %q: %v", filename, err)
		return "", err
	}
	if err := s.repo.SetVideoURL(lessonID, result.SecureURL); err != nil {
		return "", err
	}
	return result.SecureURL, nil
}

func (s *Service) UploadPDF(lessonID int, fileBytes []byte, filename string) (string, error) {
	result, err := s.cloudinaryClient.Upload(fileBytes, filename, "raw")
	if err != nil {
		log.Printf("[lessons] Cloudinary PDF upload failed for %q: %v", filename, err)
		return "", err
	}
	if err := s.repo.SetPDFURL(lessonID, result.SecureURL); err != nil {
		return "", err
	}
	return result.SecureURL, nil
}

func (s *Service) UploadAssignment(lessonID int, fileBytes []byte, filename string) (string, error) {
	result, err := s.cloudinaryClient.Upload(fileBytes, filename, "raw")
	if err != nil {
		log.Printf("[lessons] Cloudinary assignment upload failed for %q: %v", filename, err)
		return "", err
	}
	if err := s.repo.SetAssignmentURL(lessonID, result.SecureURL); err != nil {
		return "", err
	}
	return result.SecureURL, nil
}