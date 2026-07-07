// Package assignment implements Phase 1 of the Assignment & AI Auto
// Evaluation module: subject-level targeting, teacher CRUD, AI-generated
// assignment drafts, student submission + AI evaluation, and optional
// teacher review.
//
// Targeting is deliberately polymorphic (assignment_targets.target_type)
// so future phases (individual student, multiple students, batch,
// classroom, section, group) need zero schema changes - only new
// target_type values and new repository lookups.
package assignment

import "time"

// Assignment lifecycle statuses.
const (
	StatusDraft       = "draft"
	StatusPublished   = "published"
	StatusClosed      = "closed"
	StatusUnpublished = "unpublished"
	StatusArchived    = "archived"
)

// Submission statuses.
const (
	SubmissionDraft       = "draft"
	SubmissionSubmitted   = "submitted"
	SubmissionUnderReview = "under_review"
	SubmissionEvaluated   = "evaluated"
	SubmissionReturned    = "returned"
)

// TargetTypeSubject is the only target type wired up in Phase 1.
// TargetTypeStudent/Batch/Classroom/Section/Group are reserved names for
// future phases - adding them needs no schema change, just new code paths.
const (
	TargetTypeSubject   = "subject"
	TargetTypeStudent   = "student"
	TargetTypeBatch     = "batch"
	TargetTypeClassroom = "classroom"
	TargetTypeSection   = "section"
	TargetTypeGroup     = "group"
)

// Assignment mirrors an "assignments" row, with a few joined-in display
// fields (teacher/subject name, submission count) for convenience.
type Assignment struct {
	ID               int        `json:"id"`
	TeacherID        int        `json:"teacher_id"`
	TeacherName      string     `json:"teacher_name,omitempty"`
	SubjectID        *int       `json:"subject_id"`
	SubjectName      string     `json:"subject_name,omitempty"`
	Title            string     `json:"title"`
	Description      string     `json:"description"`
	Instructions     string     `json:"instructions"`
	Difficulty       string     `json:"difficulty"`
	EstimatedMinutes *int       `json:"estimated_minutes"`
	MaxMarks         int        `json:"max_marks"`
	PassingMarks     *int       `json:"passing_marks"`
	StartDate        *time.Time `json:"start_date"`
	DueDate          *time.Time `json:"due_date"`
	Status           string     `json:"status"`
	MyStatus         string     `json:"my_status,omitempty"` // student-facing only: "not_started" | submission status
	SubmissionCount  int        `json:"submission_count,omitempty"`
	MySubmissionStatus string   `json:"my_submission_status,omitempty"` // set only in student-facing lists
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

// CreateAssignmentRequest is the body for POST /api/assignments.
// SubjectID becomes the assignment's one (Phase 1) target.
type CreateAssignmentRequest struct {
	SubjectID        int    `json:"subject_id" binding:"required"`
	Title            string `json:"title" binding:"required"`
	Description      string `json:"description"`
	Instructions     string `json:"instructions"`
	Difficulty       string `json:"difficulty"`
	EstimatedMinutes int    `json:"estimated_minutes"`
	MaxMarks         int    `json:"max_marks"`
	PassingMarks     int    `json:"passing_marks"`
	StartDate        string `json:"start_date"` // ISO8601, optional
	DueDate          string `json:"due_date"`    // ISO8601, optional
}

// UpdateAssignmentRequest is the body for PUT /api/assignments/:id.
// Pointer fields mean "only update if present".
type UpdateAssignmentRequest struct {
	Title            *string `json:"title"`
	Description      *string `json:"description"`
	Instructions     *string `json:"instructions"`
	Difficulty       *string `json:"difficulty"`
	EstimatedMinutes *int    `json:"estimated_minutes"`
	MaxMarks         *int    `json:"max_marks"`
	PassingMarks     *int    `json:"passing_marks"`
	StartDate        *string `json:"start_date"`
	DueDate          *string `json:"due_date"`
}

// GenerateAssignmentRequest is the body for POST /api/assignments/generate-ai.
// Returns a draft the teacher can edit before actually creating it - it
// does NOT save anything by itself.
type GenerateAssignmentRequest struct {
	SubjectID  int    `json:"subject_id" binding:"required"`
	Topic      string `json:"topic" binding:"required"`
	Difficulty string `json:"difficulty"`
}

// GeneratedAssignmentDraft is what /generate-ai returns.
type GeneratedAssignmentDraft struct {
	Title            string `json:"title"`
	Description      string `json:"description"`
	Instructions     string `json:"instructions"`
	EstimatedMinutes int    `json:"estimated_minutes"`
}

// Submission mirrors an "assignment_submissions" row, with its
// evaluation embedded once one exists.
type Submission struct {
	ID             int         `json:"id"`
	AssignmentID   int         `json:"assignment_id"`
	StudentID      int         `json:"student_id"`
	StudentName    string      `json:"student_name,omitempty"`
	SubmissionText string      `json:"submission_text"`
	Status         string      `json:"status"`
	SubmittedAt    *time.Time  `json:"submitted_at"`
	CreatedAt      time.Time   `json:"created_at"`
	UpdatedAt      time.Time   `json:"updated_at"`
	Evaluation     *Evaluation `json:"evaluation,omitempty"`
}

// Evaluation mirrors an "assignment_evaluations" row.
type Evaluation struct {
	ID                   int        `json:"id"`
	SubmissionID         int        `json:"submission_id"`
	AIScore              *int       `json:"ai_score"`
	MaxScore             *int       `json:"max_score"`
	Percentage           *float64   `json:"percentage"`
	Strengths            []string   `json:"strengths"`
	Weaknesses           []string   `json:"weaknesses"`
	MissingConcepts      []string   `json:"missing_concepts"`
	Suggestions          string     `json:"suggestions"`
	TeacherOverrideScore *int       `json:"teacher_override_score"`
	TeacherFeedback      string     `json:"teacher_feedback"`
	ReviewedByTeacher    bool       `json:"reviewed_by_teacher"`
	EvaluatedAt          *time.Time `json:"evaluated_at"`
}

// SaveDraftRequest is the body for POST /api/assignments/:id/draft.
type SaveDraftRequest struct {
	SubmissionText string `json:"submission_text"`
}

// SubmitRequest is the body for POST /api/assignments/:id/submit.
type SubmitRequest struct {
	SubmissionText string `json:"submission_text" binding:"required"`
}

// TeacherReviewRequest is the body for POST /api/assignments/submissions/:id/review.
type TeacherReviewRequest struct {
	OverrideScore *int   `json:"override_score"`
	Feedback      string `json:"feedback"`
}

// AnalyticsOverview is real, aggregate data for teacher/admin dashboards -
// nothing estimated.
type AnalyticsOverview struct {
	TotalAssignments     int     `json:"total_assignments"`
	PublishedAssignments int     `json:"published_assignments"`
	TotalSubmissions     int     `json:"total_submissions"`
	EvaluatedSubmissions int     `json:"evaluated_submissions"`
	AverageScorePercent  float64 `json:"average_score_percent"`
}
