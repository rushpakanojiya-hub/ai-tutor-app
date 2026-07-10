package liveclass

import (
	"context"
	"fmt"
	"log"
	"time"

	"ai-tutor-backend/internal/badge"
	"ai-tutor-backend/internal/livekit"
	"ai-tutor-backend/internal/notification"
)

type Service struct {
	repo            *Repository
	notificationSvc *notification.Service
	tokenSvc        *livekit.TokenService
	roomClient      *livekit.RoomClient
	livekitURL      string
	badgeSvc        *badge.Service
}

func NewService(repo *Repository, notificationSvc *notification.Service, tokenSvc *livekit.TokenService, roomClient *livekit.RoomClient, livekitURL string, badgeSvc *badge.Service) *Service {
	return &Service{repo: repo, notificationSvc: notificationSvc, tokenSvc: tokenSvc, roomClient: roomClient, livekitURL: livekitURL, badgeSvc: badgeSvc}
}

func (s *Service) Create(teacherID int, req CreateRequest) (int, error) {
	// The "Public" toggle has been removed from the schedule form - every
	// class stays visible to students by default (unchanged existing
	// behavior), regardless of what the client sends for this field.
	req.IsPublic = true

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

// --- Real video session (LiveKit) ---

var ErrMeetingNotLive = fmt.Errorf("the teacher hasn't started this class yet")
var ErrMeetingAlreadyEnded = fmt.Errorf("this class has already ended")

func (s *Service) Start(classID, teacherID int) (*StartResponse, error) {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return nil, err
	}
	if class.TeacherID != teacherID {
		return nil, ErrForbidden
	}
	if class.MeetingStatus == MeetingEnded {
		return nil, ErrMeetingAlreadyEnded
	}
	// QA fix: cancelling a class only ever set the schedule Status to
	// "cancelled" - it never blocked Start() from also flipping
	// MeetingStatus to "live", since Start() only checked MeetingStatus.
	// A cancelled class could still be started and joined.
	if class.Status == StatusCancelled {
		return nil, ErrClassCancelled
	}

	roomName := class.RoomName
	if roomName == "" {
		roomName = fmt.Sprintf("class-%d", classID)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := s.roomClient.EnsureRoom(ctx, roomName); err != nil {
		log.Printf("[liveclass] EnsureRoom failed for room %q: %v", roomName, err)
		return nil, fmt.Errorf("could not reach LiveKit: %w", err)
	}

	if err := s.repo.SetMeetingLive(classID, teacherID, roomName); err != nil {
		log.Printf("[liveclass] SetMeetingLive DB update failed for class %d: %v", classID, err)
		return nil, err
	}

	teacherName, _ := s.repo.GetUserName(teacherID)
	token, err := s.tokenSvc.GenerateToken(roomName, fmt.Sprintf("teacher-%d", teacherID), teacherName, true)
	if err != nil {
		log.Printf("[liveclass] GenerateToken failed for teacher %d: %v", teacherID, err)
		return nil, err
	}

	return &StartResponse{Token: token, URL: s.livekitURL, RoomName: roomName}, nil
}

var ErrRoomLocked = fmt.Errorf("the teacher has locked this class to new joins")

func (s *Service) Join(classID, studentID int) (*JoinResponse, error) {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return nil, err
	}
	if class.MeetingStatus != MeetingLive {
		return nil, ErrMeetingNotLive
	}
	if class.Locked {
		return nil, ErrRoomLocked
	}

	if class.MaxStudents != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		participants, err := s.roomClient.ListParticipants(ctx, class.RoomName)
		cancel()
		if err == nil {
			teacherIdentity := fmt.Sprintf("teacher-%d", class.TeacherID)
			studentCount := 0
			for _, p := range participants {
				if p.Identity != teacherIdentity {
					studentCount++
				}
			}
			if studentCount >= *class.MaxStudents {
				return nil, ErrClassFull
			}
		}
		// If the LiveKit call itself fails, we deliberately don't block the
		// join on that - the capacity check is a nice-to-have, not a
		// reason to hard-fail joining over an unrelated infra hiccup.
	}

	studentName, _ := s.repo.GetUserName(studentID)
	token, err := s.tokenSvc.GenerateToken(class.RoomName, fmt.Sprintf("student-%d", studentID), studentName, false)
	if err != nil {
		return nil, err
	}

	_ = s.repo.CheckIn(classID, studentID, AttendancePresent) // best-effort, real join = present
	go s.badgeSvc.CheckAndAwardBadges(studentID)

	return &JoinResponse{Token: token, URL: s.livekitURL, RoomName: class.RoomName}, nil
}

func (s *Service) End(classID, teacherID int) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if class.TeacherID != teacherID {
		return ErrForbidden
	}

	if class.RoomName != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = s.roomClient.EndRoom(ctx, class.RoomName) // best-effort - still mark ended even if this fails
	}

	if err := s.repo.SetMeetingEnded(classID, teacherID); err != nil {
		return err
	}

	// meeting_status and status (scheduled/completed) are separate
	// columns - without also completing the schedule status here, the
	// class stayed in "Upcoming" (Join/I'm Present buttons still shown)
	// forever after the meeting genuinely ended. Ending the meeting is
	// exactly the "class is done" signal - it should always land in
	// Past Classes, so a teacher never needs a second manual step, and
	// this ALSO doubles as the "teacher cannot reopen the same meeting"
	// guard (Start() already refuses once status leaves 'scheduled').
	return s.repo.SetStatus(classID, teacherID, StatusCompleted)
}

func (s *Service) GetMeetingStatus(classID int) (string, error) {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return "", err
	}
	return class.MeetingStatus, nil
}

// --- Teacher moderation ---

func (s *Service) MuteParticipant(classID, teacherID int, targetIdentity string) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if class.TeacherID != teacherID {
		return ErrForbidden
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return s.roomClient.MuteParticipant(ctx, class.RoomName, targetIdentity)
}

func (s *Service) RemoveParticipant(classID, teacherID int, targetIdentity string) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if class.TeacherID != teacherID {
		return ErrForbidden
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return s.roomClient.RemoveParticipant(ctx, class.RoomName, targetIdentity)
}

func (s *Service) MuteAll(classID, teacherID int) error {
	class, err := s.repo.GetByID(classID)
	if err != nil {
		return err
	}
	if class.TeacherID != teacherID {
		return ErrForbidden
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return s.roomClient.MuteAllExcept(ctx, class.RoomName, fmt.Sprintf("teacher-%d", teacherID))
}

func (s *Service) SetLocked(classID, teacherID int, locked bool) error {
	return s.repo.SetLocked(classID, teacherID, locked)
}

// --- Attendance ---

var ErrAttendanceWindowClosed = fmt.Errorf("check-in is only available during the scheduled class time")

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
	go s.badgeSvc.CheckAndAwardBadges(studentID)
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
