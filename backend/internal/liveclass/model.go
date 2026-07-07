// Package liveclass implements Phase 1 of Live Classes: scheduling and
// calendar only - no video/whiteboard/screen-share/recording, since
// those need a third-party video SDK (Agora/100ms/LiveKit/Daily.co) that
// isn't set up yet. "Start Class"/"Join Class" aren't implemented here on
// purpose - they'd be dead buttons without real video behind them.
package liveclass

import "time"

const (
	StatusScheduled = "scheduled"
	StatusCompleted = "completed"
	StatusCancelled = "cancelled"
	// "missed" isn't stored - it's computed at query time for any class
	// whose end time has passed while still "scheduled".
	StatusMissed = "missed"
)

type LiveClass struct {
	ID              int       `json:"id"`
	TeacherID       int       `json:"teacher_id"`
	TeacherName     string    `json:"teacher_name,omitempty"`
	SubjectID       *int      `json:"subject_id"`
	SubjectName     string    `json:"subject_name,omitempty"`
	LessonID        *int      `json:"lesson_id"`
	LessonTitle     string    `json:"lesson_title,omitempty"`
	Title           string    `json:"title"`
	Description     string    `json:"description"`
	ClassDate       string    `json:"class_date"` // YYYY-MM-DD
	StartTime       string    `json:"start_time"` // HH:MM
	EndTime         string    `json:"end_time"`   // HH:MM
	MaxStudents     *int      `json:"max_students"`
	IsPublic        bool      `json:"is_public"`
	HasPassword     bool      `json:"has_password"`
	RecordClass     bool      `json:"record_class"`
	Status          string    `json:"status"` // scheduled | completed | cancelled | missed (computed)
	CreatedAt       time.Time `json:"created_at"`
}

type CreateRequest struct {
	SubjectID       int    `json:"subject_id" binding:"required"`
	LessonID        int    `json:"lesson_id"`
	Title           string `json:"title" binding:"required"`
	Description     string `json:"description"`
	ClassDate       string `json:"class_date" binding:"required"` // YYYY-MM-DD
	StartTime       string `json:"start_time" binding:"required"` // HH:MM
	EndTime         string `json:"end_time" binding:"required"`   // HH:MM
	MaxStudents     int    `json:"max_students"`
	IsPublic        bool   `json:"is_public"`
	MeetingPassword string `json:"meeting_password"`
	RecordClass     bool   `json:"record_class"`
}

type UpdateRequest struct {
	Title           *string `json:"title"`
	Description     *string `json:"description"`
	ClassDate       *string `json:"class_date"`
	StartTime       *string `json:"start_time"`
	EndTime         *string `json:"end_time"`
	MaxStudents     *int    `json:"max_students"`
	IsPublic        *bool   `json:"is_public"`
	MeetingPassword *string `json:"meeting_password"`
	RecordClass     *bool   `json:"record_class"`
}

// AttendanceStatus values - "absent" is never stored, only computed by
// its absence once a class has ended.
const (
	AttendancePresent = "present"
	AttendanceLate    = "late"
)

type AttendanceRecord struct {
	StudentID   int       `json:"student_id"`
	StudentName string    `json:"student_name"`
	CheckedInAt time.Time `json:"checked_in_at"`
	Status      string    `json:"status"` // present | late
}

type MyAttendance struct {
	CheckedIn   bool       `json:"checked_in"`
	Status      string     `json:"status,omitempty"`
	CheckedInAt *time.Time `json:"checked_in_at,omitempty"`
}

// AttendanceSummary is a student's overall attendance across every class
// that has already ended.
type AttendanceSummary struct {
	TotalCompletedClasses int     `json:"total_completed_classes"`
	AttendedCount         int     `json:"attended_count"`
	Percentage            float64 `json:"percentage"`
}
