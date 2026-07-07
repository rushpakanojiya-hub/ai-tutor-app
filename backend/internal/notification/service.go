package notification

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) NotifyOne(userID int, notifType, title, body string, relatedID int) error {
	return s.repo.Create(userID, notifType, title, body, relatedID)
}

// NotifyAllStudents fans a notification out to every student - used for
// "new live class scheduled" / "live class cancelled", since this app
// has no per-class enrollment to narrow the audience further.
func (s *Service) NotifyAllStudents(notifType, title, body string, relatedID int) error {
	ids, err := s.repo.AllStudentIDs()
	if err != nil {
		return err
	}
	return s.repo.CreateForUsers(ids, notifType, title, body, relatedID)
}

func (s *Service) ListForUser(userID int) ([]Notification, error) {
	return s.repo.ListForUser(userID)
}

func (s *Service) CountUnread(userID int) (int, error) {
	return s.repo.CountUnread(userID)
}

func (s *Service) MarkRead(id, userID int) error {
	return s.repo.MarkRead(id, userID)
}

func (s *Service) MarkAllRead(userID int) error {
	return s.repo.MarkAllRead(userID)
}
