package progress

import (
	"ai-tutor-backend/internal/enrollment"
	"ai-tutor-backend/internal/streak"
)

// Service contains the business logic for progress tracking.
type Service struct {
	repo          *Repository
	streakSvc     *streak.Service
	enrollmentSvc *enrollment.Service
}

// NewService wires a Repository, the shared streak Service, and the
// shared enrollment Service into a progress Service.
func NewService(repo *Repository, streakSvc *streak.Service, enrollmentSvc *enrollment.Service) *Service {
	return &Service{repo: repo, streakSvc: streakSvc, enrollmentSvc: enrollmentSvc}
}

// MarkLessonComplete records lessonID as completed by userID, with an
// optional quiz score (nil if the lesson has no quiz or it wasn't taken).
// Also marks today as an active day for the Learning Streak, and enrolls
// the student in the lesson's subject (see internal/enrollment) - the
// signal that makes them "eligible" to see that subject's assignments.
func (s *Service) MarkLessonComplete(userID, lessonID int, score *int) error {
	if err := s.repo.MarkComplete(userID, lessonID, score); err != nil {
		return err
	}
	_ = s.streakSvc.RecordActivity(userID) // best-effort

	if subjectID, err := s.repo.GetLessonSubjectID(lessonID); err == nil {
		_ = s.enrollmentSvc.EnsureEnrolled(userID, subjectID) // best-effort
	}
	return nil
}

// SubjectProgress returns userID's completion summary for a subject.
func (s *Service) SubjectProgress(userID, subjectID int) (*SubjectProgress, error) {
	return s.repo.GetSubjectProgress(userID, subjectID)
}
