package liveclass

import (
	"fmt"
	"time"

	"ai-tutor-backend/internal/notification"
)

type Service struct {
	repo            *Repository
	notificationSvc *notification.Service
}

func NewService(repo *Repository, notificationSvc *notification.Service) *Service {
	return &Service{repo: repo, notificationSvc: notificationSvc}
}

func (s *Service) Create(teacherID int, req CreateRequest) (int, error) {
	id, err := s.repo.Create(teacherID, req)
	if err != nil {
		return 0, err
	}
	_ = s.notificationSvc.NotifyAllStudents(
		notification.TypeNewLiveClass,
		"New Live Class Scheduled",
		fmt.Sprintf("%s on %s at %s", req.Title, req.ClassDate, req.StartTime),
		id,
	) // best-effort
	return id, nil
}

func (s *Service) Update(classID, teacherID int, req UpdateRequest) error {
	return s.repo.Update(classID, teacherID, req)
}

func (s *Service) Cancel(classID, teacherID int) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if err := s.repo.SetStatus(classID, teacherID, StatusCancelled); err != nil {
		return err
	}
	_ = s.notificationSvc.NotifyAllStudents(
		notification.TypeLiveClassCancelled,
		"Live Class Cancelled",
		fmt.Sprintf("%s on %s has been cancelled", class.Title, class.ClassDate),
		classID,
	) // best-effort
	return nil
}

// AdminCancel lets an admin cancel any class platform-wide, bypassing
// the teacher-ownership check.
func (s *Service) AdminCancel(classID int) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if err := s.repo.AdminCancel(classID); err != nil {
		return err
	}
	_ = s.notificationSvc.NotifyAllStudents(
		notification.TypeLiveClassCancelled,
		"Live Class Cancelled",
		fmt.Sprintf("%s on %s has been cancelled", class.Title, class.ClassDate),
		classID,
	) // best-effort
	return nil
}

func (s *Service) MarkCompleted(classID, teacherID int) error {
	return s.repo.SetStatus(classID, teacherID, StatusCompleted)
}

func (s *Service) Delete(classID, teacherID int) error {
	return s.repo.Delete(classID, teacherID)
}

func (s *Service) GetByID(classID int) (*LiveClass, error) {
	return s.repo.GetByID(classID)
}

func (s *Service) ListForTeacher(teacherID int) ([]LiveClass, error) {
	return s.repo.ListForTeacher(teacherID)
}

func (s *Service) ListForStudent() ([]LiveClass, error) {
	return s.repo.ListForStudent()
}

func (s *Service) ListAllForAdmin() ([]LiveClass, error) {
	return s.repo.ListAllForAdmin()
}

// --- Attendance ---

var ErrAttendanceWindowClosed = fmt.Errorf("check-in is only available during the scheduled class time")

// CheckIn validates the class window (now must be between start and end
// time on class_date) before recording attendance. Checking in within
// the first 10 minutes counts as "present", after that as "late".
func (s *Service) CheckIn(classID, studentID int) (string, error) {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return "", err
	}

	loc := time.Now().Location()
	dateParts := parseDateParts(class.ClassDate)
	startParts := parseTimeParts(class.StartTime)
	endParts := parseTimeParts(class.EndTime)
	if dateParts == nil || startParts == nil || endParts == nil {
		return "", fmt.Errorf("invalid class schedule data")
	}

	start := time.Date(dateParts[0], time.Month(dateParts[1]), dateParts[2], startParts[0], startParts[1], 0, 0, loc)
	end := time.Date(dateParts[0], time.Month(dateParts[1]), dateParts[2], endParts[0], endParts[1], 0, 0, loc)
	now := time.Now()

	if now.Before(start) || now.After(end) {
		return "", ErrAttendanceWindowClosed
	}

	status := AttendancePresent
	if now.After(start.Add(10 * time.Minute)) {
		status = AttendanceLate
	}

	if err := s.repo.CheckIn(classID, studentID, status); err != nil {
		return "", err
	}
	return status, nil
}

func parseDateParts(s string) []int {
	var y, m, d int
	if _, err := fmt.Sscanf(s, "%d-%d-%d", &y, &m, &d); err != nil {
		return nil
	}
	return []int{y, m, d}
}

func parseTimeParts(s string) []int {
	var h, m int
	if _, err := fmt.Sscanf(s, "%d:%d", &h, &m); err != nil {
		return nil
	}
	return []int{h, m}
}

func (s *Service) GetMyAttendance(classID, studentID int) (*MyAttendance, error) {
	rec, err := s.repo.GetMyAttendance(classID, studentID)
	if err != nil {
		return nil, err
	}
	if rec == nil {
		return &MyAttendance{CheckedIn: false}, nil
	}
	return &MyAttendance{CheckedIn: true, Status: rec.Status, CheckedInAt: &rec.CheckedInAt}, nil
}

func (s *Service) ListAttendanceForClass(classID, teacherID int) ([]AttendanceRecord, error) {
	return s.repo.ListAttendanceForClass(classID, teacherID)
}

func (s *Service) GetAttendanceSummaryForStudent(studentID int) (*AttendanceSummary, error) {
	return s.repo.GetAttendanceSummaryForStudent(studentID)
}
