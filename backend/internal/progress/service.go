package progress

import "ai-tutor-backend/internal/streak"

// Service contains the business logic for progress tracking.
type Service struct {
	repo      *Repository
	streakSvc *streak.Service
}

// NewService wires a Repository and the shared streak Service into a
// progress Service.
func NewService(repo *Repository, streakSvc *streak.Service) *Service {
	return &Service{repo: repo, streakSvc: streakSvc}
}

// MarkLessonComplete records lessonID as completed by userID, with an
// optional quiz score (nil if the lesson has no quiz or it wasn't taken).
// Also marks today as an active day for the Learning Streak.
func (s *Service) MarkLessonComplete(userID, lessonID int, score *int) error {
	if err := s.repo.MarkComplete(userID, lessonID, score); err != nil {
		return err
	}
	_ = s.streakSvc.RecordActivity(userID) // best-effort - a streak-recording hiccup shouldn't fail lesson completion
	return nil
}

// SubjectProgress returns userID's completion summary for a subject.
func (s *Service) SubjectProgress(userID, subjectID int) (*SubjectProgress, error) {
	return s.repo.GetSubjectProgress(userID, subjectID)
}
