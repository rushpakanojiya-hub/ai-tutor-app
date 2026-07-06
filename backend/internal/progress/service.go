package progress

// Service contains the business logic for progress tracking.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a progress Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// MarkLessonComplete records lessonID as completed by userID, with an
// optional quiz score (nil if the lesson has no quiz or it wasn't taken).
func (s *Service) MarkLessonComplete(userID, lessonID int, score *int) error {
	return s.repo.MarkComplete(userID, lessonID, score)
}

// SubjectProgress returns userID's completion summary for a subject.
func (s *Service) SubjectProgress(userID, subjectID int) (*SubjectProgress, error) {
	return s.repo.GetSubjectProgress(userID, subjectID)
}
