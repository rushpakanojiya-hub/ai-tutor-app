package progress

import (
	"ai-tutor-backend/internal/badge"
	"ai-tutor-backend/internal/enrollment"
	"ai-tutor-backend/internal/streak"
	"ai-tutor-backend/internal/xp"
)

// Service contains the business logic for progress tracking.
type Service struct {
	repo          *Repository
	streakSvc     *streak.Service
	enrollmentSvc *enrollment.Service
	badgeSvc      *badge.Service
	xpSvc         *xp.Service
}

// NewService wires a Repository, the shared streak Service, the shared
// enrollment Service, and the shared badge Service into a progress Service.
func NewService(repo *Repository, streakSvc *streak.Service, enrollmentSvc *enrollment.Service, badgeSvc *badge.Service, xpSvc *xp.Service) *Service {
	return &Service{repo: repo, streakSvc: streakSvc, enrollmentSvc: enrollmentSvc, badgeSvc: badgeSvc, xpSvc: xpSvc}
}

// MarkLessonComplete records lessonID as completed by userID, with an
// optional quiz score (nil if the lesson has no quiz or it wasn't taken).
// Also marks today as an active day for the Learning Streak, enrolls the
// student in the lesson's subject, and checks for newly-earned badges.
func (s *Service) MarkLessonComplete(userID, lessonID int, score *int) error {
	if err := s.repo.MarkComplete(userID, lessonID, score); err != nil {
		return err
	}
	_ = s.streakSvc.RecordActivity(userID) // best-effort

	if subjectID, err := s.repo.GetLessonSubjectID(lessonID); err == nil {
		_ = s.enrollmentSvc.EnsureEnrolled(userID, subjectID) // best-effort
		go s.xpSvc.CheckAndAwardCourseCompletion(userID, subjectID)
	}
	go s.badgeSvc.CheckAndAwardBadges(userID)
	go s.xpSvc.OnStudyActivity(userID)
	return nil
}

// SubjectProgress returns userID's completion summary for a subject.
func (s *Service) SubjectProgress(userID, subjectID int) (*SubjectProgress, error) {
	return s.repo.GetSubjectProgress(userID, subjectID)
}
