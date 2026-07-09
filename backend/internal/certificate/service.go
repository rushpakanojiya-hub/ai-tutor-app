package certificate

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// CheckAndGenerate is the auto-generation hook - called (fire-and-forget)
// after a lesson is marked complete, same pattern as badges/XP. Only
// actually creates a certificate the FIRST time a student crosses both
// bars for a given subject (100% lessons + passing average quiz score);
// every call after that is a safe no-op via the DB's UNIQUE constraint.
func (s *Service) CheckAndGenerate(studentID, subjectID int) {
	hasCert, err := s.repo.HasCertificate(studentID, subjectID)
	if err != nil || hasCert {
		return
	}

	completed, err := s.repo.IsSubjectFullyCompleted(studentID, subjectID)
	if err != nil || !completed {
		return
	}

	finalScore, hasScore, err := s.repo.GetFinalScore(studentID, subjectID)
	if err != nil || !hasScore || finalScore < passingScore {
		return
	}

	courseName, subjectName, err := s.repo.GetCourseAndSubjectName(subjectID)
	if err != nil {
		return
	}
	instructorName, err := s.repo.GetInstructorName(subjectID)
	if err != nil {
		instructorName = "AI Tutor Faculty"
	}
	completionDate, err := s.repo.GetCompletionDate(studentID, subjectID)
	if err != nil || completionDate == "" {
		return
	}

	_, _ = s.repo.Create(studentID, subjectID, courseName, subjectName, instructorName, finalScore, completionDate)
}

func (s *Service) ListForStudent(studentID int) ([]Certificate, error) {
	return s.repo.ListForStudent(studentID)
}

func (s *Service) ListForTeacher(teacherID int) ([]Certificate, error) {
	return s.repo.ListForTeacher(teacherID)
}

func (s *Service) ListAll() ([]Certificate, error) {
	return s.repo.ListAll()
}

// GetForViewing enforces role-based access: students can only ever open
// their own certificate; teachers only ones in subjects they're active
// in; admins can open any.
func (s *Service) GetForViewing(certID, requestingUserID int, requestingRole string) (*Certificate, error) {
	cert, err := s.repo.GetByID(certID)
	if err != nil {
		return nil, err
	}

	switch requestingRole {
	case "admin":
		return cert, nil
	case "student":
		if cert.StudentID != requestingUserID {
			return nil, ErrNotFound // don't leak existence to a non-owner
		}
		return cert, nil
	case "teacher":
		teacherCerts, err := s.repo.ListForTeacher(requestingUserID)
		if err != nil {
			return nil, err
		}
		for _, c := range teacherCerts {
			if c.ID == certID {
				return cert, nil
			}
		}
		return nil, ErrNotFound
	default:
		return nil, ErrNotFound
	}
}
