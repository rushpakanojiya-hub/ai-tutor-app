# apply_assignment_fixes.ps1
# Run from your backend project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\backend)
# Writes: assignment module fixes (transactions, RowsAffected checks, date validation,
# SaveDraft published-status gate, fixed Atoi error handling).
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying assignment module fixes in $root" -ForegroundColor Cyan

# --- internal/assignment/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/assignment") | Out-Null
$content_internal_assignment_repository_go = @'
package assignment

import (
	"database/sql"
	"encoding/json"
	"errors"
	"time"
)

var ErrNotFound = errors.New("assignment not found")
var ErrForbidden = errors.New("you don't have permission to do that")
var ErrCannotDelete = errors.New("published assignments must be archived before they can be deleted")
var ErrHasSubmissions = errors.New("cannot unpublish an assignment that already has submissions")

// ErrInvalidDate is returned when start_date/due_date isn't empty but
// also isn't a valid ISO8601/RFC3339 timestamp.
//
// BUG FIX: parseOptionalTime used to swallow a parse failure by silently
// returning nil (treated as "no date given"). A teacher who mistyped a
// due date would have it silently vanish with no error - the assignment
// would just quietly save with no due date at all.
var ErrInvalidDate = errors.New("start_date/due_date must be a valid ISO8601 timestamp")

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func parseOptionalTime(s string) (*time.Time, error) {
	if s == "" {
		return nil, nil
	}
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return nil, ErrInvalidDate
	}
	return &t, nil
}

func parseOptionalTimePtr(s *string) (*time.Time, error) {
	if s == nil {
		return nil, nil
	}
	return parseOptionalTime(*s)
}

func (r *Repository) CreateAssignment(teacherID int, req CreateAssignmentRequest) (int, error) {
	// BUG FIX: validate dates BEFORE opening a transaction - fail fast
	// with a clear error instead of silently dropping a mistyped date.
	startDate, err := parseOptionalTime(req.StartDate)
	if err != nil {
		return 0, err
	}
	dueDate, err := parseOptionalTime(req.DueDate)
	if err != nil {
		return 0, err
	}

	tx, err := r.db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	difficulty := req.Difficulty
	if difficulty == "" {
		difficulty = "medium"
	}

	var id int
	err = tx.QueryRow(`
		INSERT INTO assignments (teacher_id, title, description, instructions, difficulty, estimated_minutes, max_marks, passing_marks, start_date, due_date, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING id`,
		teacherID, req.Title, req.Description, req.Instructions, difficulty,
		nullIfZeroInt(req.EstimatedMinutes), maxMarksOrDefault(req.MaxMarks), nullIfZeroInt(req.PassingMarks),
		startDate, dueDate, StatusDraft,
	).Scan(&id)
	if err != nil {
		return 0, err
	}

	_, err = tx.Exec(`
		INSERT INTO assignment_targets (assignment_id, target_type, target_id)
		VALUES ($1, $2, $3)`,
		id, TargetTypeSubject, req.SubjectID,
	)
	if err != nil {
		return 0, err
	}

	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return id, nil
}

func nullIfZeroInt(n int) interface{} {
	if n == 0 {
		return nil
	}
	return n
}

func maxMarksOrDefault(n int) int {
	if n <= 0 {
		return 10
	}
	return n
}

func (r *Repository) checkOwnership(assignmentID, teacherID int) error {
	var ownerID int
	err := r.db.QueryRow(`SELECT teacher_id FROM assignments WHERE id = $1`, assignmentID).Scan(&ownerID)
	if err == sql.ErrNoRows {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if ownerID != teacherID {
		return ErrForbidden
	}
	return nil
}

func (r *Repository) UpdateAssignment(assignmentID, teacherID int, req UpdateAssignmentRequest) error {
	if err := r.checkOwnership(assignmentID, teacherID); err != nil {
		return err
	}

	// BUG FIX: same silent-date-drop issue as CreateAssignment above.
	startDate, err := parseOptionalTimePtr(req.StartDate)
	if err != nil {
		return err
	}
	dueDate, err := parseOptionalTimePtr(req.DueDate)
	if err != nil {
		return err
	}

	_, err = r.db.Exec(`
		UPDATE assignments SET
			title = COALESCE($1, title),
			description = COALESCE($2, description),
			instructions = COALESCE($3, instructions),
			difficulty = COALESCE($4, difficulty),
			estimated_minutes = COALESCE($5, estimated_minutes),
			max_marks = COALESCE($6, max_marks),
			passing_marks = COALESCE($7, passing_marks),
			start_date = COALESCE($8, start_date),
			due_date = COALESCE($9, due_date),
			updated_at = now()
		WHERE id = $10`,
		req.Title, req.Description, req.Instructions, req.Difficulty,
		req.EstimatedMinutes, req.MaxMarks, req.PassingMarks,
		startDate, dueDate, assignmentID,
	)
	return err
}

func (r *Repository) DeleteAssignment(assignmentID, teacherID int) error {
	if err := r.checkOwnership(assignmentID, teacherID); err != nil {
		return err
	}
	var status string
	if err := r.db.QueryRow(`SELECT status FROM assignments WHERE id = $1`, assignmentID).Scan(&status); err != nil {
		return err
	}
	if status != StatusDraft && status != StatusArchived {
		return ErrCannotDelete
	}
	_, err := r.db.Exec(`DELETE FROM assignments WHERE id = $1`, assignmentID)
	return err
}

func (r *Repository) HasSubmissions(assignmentID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM assignment_submissions WHERE assignment_id = $1 AND status != 'draft')`, assignmentID).Scan(&exists)
	return exists, err
}

func (r *Repository) SetStatus(assignmentID, teacherID int, status string) error {
	if err := r.checkOwnership(assignmentID, teacherID); err != nil {
		return err
	}
	_, err := r.db.Exec(`UPDATE assignments SET status = $1, updated_at = now() WHERE id = $2`, status, assignmentID)
	return err
}

const assignmentSelect = `
	SELECT a.id, a.teacher_id, u.name, t.target_id, s.name,
	       a.title, a.description, a.instructions, a.difficulty, a.estimated_minutes,
	       a.max_marks, a.passing_marks, a.start_date, a.due_date, a.status,
	       COALESCE((SELECT COUNT(*) FROM assignment_submissions sub WHERE sub.assignment_id = a.id), 0),
	       a.created_at, a.updated_at
	FROM assignments a
	JOIN users u ON u.id = a.teacher_id
	LEFT JOIN assignment_targets t ON t.assignment_id = a.id AND t.target_type = 'subject'
	LEFT JOIN subjects s ON s.id = t.target_id
`

func assignmentSelectForStudent(studentIDPlaceholder string) string {
	return `
	SELECT a.id, a.teacher_id, u.name, t.target_id, s.name,
	       a.title, a.description, a.instructions, a.difficulty, a.estimated_minutes,
	       a.max_marks, a.passing_marks, a.start_date, a.due_date, a.status,
	       COALESCE((SELECT COUNT(*) FROM assignment_submissions sub WHERE sub.assignment_id = a.id), 0),
	       a.created_at, a.updated_at,
	       COALESCE((SELECT sub2.status FROM assignment_submissions sub2 WHERE sub2.assignment_id = a.id AND sub2.student_id = ` + studentIDPlaceholder + `), 'not_started')
	FROM assignments a
	JOIN users u ON u.id = a.teacher_id
	LEFT JOIN assignment_targets t ON t.assignment_id = a.id AND t.target_type = 'subject'
	LEFT JOIN subjects s ON s.id = t.target_id
`
}

func scanAssignmentWithMyStatus(row interface{ Scan(...any) error }) (Assignment, error) {
	var a Assignment
	var subjectID sql.NullInt64
	var subjectName sql.NullString
	err := row.Scan(
		&a.ID, &a.TeacherID, &a.TeacherName, &subjectID, &subjectName,
		&a.Title, &a.Description, &a.Instructions, &a.Difficulty, &a.EstimatedMinutes,
		&a.MaxMarks, &a.PassingMarks, &a.StartDate, &a.DueDate, &a.Status,
		&a.SubmissionCount, &a.CreatedAt, &a.UpdatedAt, &a.MyStatus,
	)
	if subjectID.Valid {
		id := int(subjectID.Int64)
		a.SubjectID = &id
	}
	a.SubjectName = subjectName.String
	return a, err
}

func scanAssignment(row interface{ Scan(...any) error }) (Assignment, error) {
	var a Assignment
	var subjectID sql.NullInt64
	var subjectName sql.NullString
	err := row.Scan(
		&a.ID, &a.TeacherID, &a.TeacherName, &subjectID, &subjectName,
		&a.Title, &a.Description, &a.Instructions, &a.Difficulty, &a.EstimatedMinutes,
		&a.MaxMarks, &a.PassingMarks, &a.StartDate, &a.DueDate, &a.Status,
		&a.SubmissionCount, &a.CreatedAt, &a.UpdatedAt,
	)
	if subjectID.Valid {
		id := int(subjectID.Int64)
		a.SubjectID = &id
	}
	a.SubjectName = subjectName.String
	return a, err
}

func (r *Repository) GetByID(assignmentID int) (*Assignment, error) {
	row := r.db.QueryRow(assignmentSelect+` WHERE a.id = $1`, assignmentID)
	a, err := scanAssignment(row)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &a, nil
}

func (r *Repository) ListForTeacher(teacherID int) ([]Assignment, error) {
	rows, err := r.db.Query(assignmentSelect+` WHERE a.teacher_id = $1 ORDER BY a.created_at DESC`, teacherID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanAssignmentRows(rows)
}

func (r *Repository) ListPublishedForSubject(subjectID, studentID int) ([]Assignment, error) {
	rows, err := r.db.Query(assignmentSelectForStudent("$2")+`
		WHERE t.target_type = 'subject' AND t.target_id = $1 AND a.status = 'published'
		ORDER BY a.due_date ASC NULLS LAST, a.created_at DESC`, subjectID, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Assignment
	for rows.Next() {
		a, err := scanAssignmentWithMyStatus(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, a)
	}
	return result, rows.Err()
}

func (r *Repository) ListPublishedForStudent(studentID int) ([]Assignment, error) {
	rows, err := r.db.Query(assignmentSelectForStudent("$1")+`
		WHERE t.target_type = 'subject' AND a.status = 'published'
		ORDER BY a.due_date ASC NULLS LAST, a.created_at DESC`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Assignment
	for rows.Next() {
		a, err := scanAssignmentWithMyStatus(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, a)
	}
	return result, rows.Err()
}

func (r *Repository) ListAllForAdmin() ([]Assignment, error) {
	rows, err := r.db.Query(assignmentSelect + ` ORDER BY a.created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanAssignmentRows(rows)
}

func (r *Repository) GetTargetSubjectID(assignmentID int) (int, error) {
	var subjectID int
	err := r.db.QueryRow(`
		SELECT target_id FROM assignment_targets
		WHERE assignment_id = $1 AND target_type = 'subject' LIMIT 1`, assignmentID).Scan(&subjectID)
	return subjectID, err
}

// BUG FIX: was missing a rows.Err() check after the scan loop.
func (r *Repository) GetEnrolledStudentIDs(subjectID int) ([]int, error) {
	rows, err := r.db.Query(`SELECT student_id FROM subject_enrollments WHERE subject_id = $1`, subjectID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return ids, nil
}

func (r *Repository) GetSubmissionStudentID(submissionID int) (int, error) {
	var studentID int
	err := r.db.QueryRow(`SELECT student_id FROM assignment_submissions WHERE id = $1`, submissionID).Scan(&studentID)
	return studentID, err
}

// BUG FIX: the per-assignment "what's my submission status" lookup used
// to discard its error entirely (`_ = r.db.QueryRow(...).Scan(...)`) - any
// failure other than "no rows" (e.g. a dropped connection mid-loop) was
// silently swallowed, showing the student an empty/blank status instead
// of a real error. sql.ErrNoRows is still the expected/normal case
// (no submission yet) and is not an error here.
func (r *Repository) ListForStudent(studentID int) ([]Assignment, error) {
	rows, err := r.db.Query(assignmentSelect+`
		WHERE t.target_type = 'subject' AND a.status IN ('published', 'closed')
		AND EXISTS (SELECT 1 FROM subject_enrollments se WHERE se.student_id = $1 AND se.subject_id = t.target_id)
		ORDER BY a.due_date ASC NULLS LAST, a.created_at DESC`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	assignments, err := scanAssignmentRows(rows)
	if err != nil {
		return nil, err
	}

	for i := range assignments {
		var status sql.NullString
		err := r.db.QueryRow(`SELECT status FROM assignment_submissions WHERE assignment_id = $1 AND student_id = $2`,
			assignments[i].ID, studentID).Scan(&status)
		if err != nil && err != sql.ErrNoRows {
			return nil, err
		}
		assignments[i].MySubmissionStatus = status.String
	}

	return assignments, nil
}

func scanAssignmentRows(rows *sql.Rows) ([]Assignment, error) {
	var result []Assignment
	for rows.Next() {
		a, err := scanAssignment(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, a)
	}
	return result, rows.Err()
}

// --- Submissions ---

// UpsertDraft saves/updates a student's in-progress draft.
//
// BUG FIX: didn't check RowsAffected. The UPDATE half of this upsert is
// guarded by "WHERE assignment_submissions.status = 'draft'" - so once a
// submission has moved past draft (submitted/evaluated/returned), the
// UPDATE branch silently matches 0 rows and the whole statement still
// reports success. A student re-opening an already-submitted assignment
// and typing in the draft box would see "saved" while nothing was
// actually written. Returns ErrAssignmentNotOpen in that case instead.
func (r *Repository) UpsertDraft(assignmentID, studentID int, text string) error {
	res, err := r.db.Exec(`
		INSERT INTO assignment_submissions (assignment_id, student_id, submission_text, status)
		VALUES ($1, $2, $3, 'draft')
		ON CONFLICT (assignment_id, student_id) DO UPDATE SET
			submission_text = EXCLUDED.submission_text,
			updated_at = now()
		WHERE assignment_submissions.status = 'draft'`,
		assignmentID, studentID, text,
	)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrAssignmentNotOpen
	}
	return nil
}

func (r *Repository) SubmitFinal(assignmentID, studentID int, text string) (int, error) {
	var id int
	err := r.db.QueryRow(`
		INSERT INTO assignment_submissions (assignment_id, student_id, submission_text, status, submitted_at)
		VALUES ($1, $2, $3, 'submitted', now())
		ON CONFLICT (assignment_id, student_id) DO UPDATE SET
			submission_text = EXCLUDED.submission_text,
			status = 'submitted',
			submitted_at = now(),
			updated_at = now()
		RETURNING id`,
		assignmentID, studentID, text,
	).Scan(&id)
	return id, err
}

func (r *Repository) GetSubmissionByAssignmentAndStudent(assignmentID, studentID int) (*Submission, error) {
	row := r.db.QueryRow(`
		SELECT id, assignment_id, student_id, submission_text, status, submitted_at, created_at, updated_at
		FROM assignment_submissions WHERE assignment_id = $1 AND student_id = $2`, assignmentID, studentID)
	return scanSubmissionWithEval(r, row)
}

func (r *Repository) GetSubmissionByID(submissionID int) (*Submission, error) {
	row := r.db.QueryRow(`
		SELECT id, assignment_id, student_id, submission_text, status, submitted_at, created_at, updated_at
		FROM assignment_submissions WHERE id = $1`, submissionID)
	return scanSubmissionWithEval(r, row)
}

func scanSubmissionWithEval(r *Repository, row *sql.Row) (*Submission, error) {
	var s Submission
	err := row.Scan(&s.ID, &s.AssignmentID, &s.StudentID, &s.SubmissionText, &s.Status, &s.SubmittedAt, &s.CreatedAt, &s.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	eval, err := r.GetEvaluationBySubmission(s.ID)
	if err == nil {
		s.Evaluation = eval
	}
	return &s, nil
}

// BUG FIX: was missing a rows.Err() check after the scan loop.
func (r *Repository) ListSubmissionsForAssignment(assignmentID, teacherID int) ([]Submission, error) {
	if err := r.checkOwnership(assignmentID, teacherID); err != nil {
		return nil, err
	}

	rows, err := r.db.Query(`
		SELECT sub.id, sub.assignment_id, sub.student_id, u.name, sub.submission_text, sub.status, sub.submitted_at, sub.created_at, sub.updated_at
		FROM assignment_submissions sub
		JOIN users u ON u.id = sub.student_id
		WHERE sub.assignment_id = $1 AND sub.status != 'draft'
		ORDER BY sub.submitted_at DESC`, assignmentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Submission
	for rows.Next() {
		var s Submission
		if err := rows.Scan(&s.ID, &s.AssignmentID, &s.StudentID, &s.StudentName, &s.SubmissionText, &s.Status, &s.SubmittedAt, &s.CreatedAt, &s.UpdatedAt); err != nil {
			return nil, err
		}
		eval, err := r.GetEvaluationBySubmission(s.ID)
		if err == nil {
			s.Evaluation = eval
		}
		result = append(result, s)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// --- Evaluations ---

// SaveAIEvaluation writes the AI's evaluation and marks the submission
// 'evaluated'.
//
// BUG FIX: these were two independent Exec calls with no transaction. If
// the second (marking the submission 'evaluated') failed after the first
// succeeded, the evaluation row would exist but the submission would be
// stuck showing 'submitted' forever - an inconsistent state with no way
// to recover except manual DB intervention. Now atomic: either both
// happen, or neither does.
func (r *Repository) SaveAIEvaluation(submissionID, aiScore, maxScore int, strengths, weaknesses, missingConcepts []string, suggestions string) error {
	strengthsJSON, _ := json.Marshal(strengths)
	weaknessesJSON, _ := json.Marshal(weaknesses)
	missingJSON, _ := json.Marshal(missingConcepts)

	percentage := 0.0
	if maxScore > 0 {
		percentage = (float64(aiScore) / float64(maxScore)) * 100
	}

	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec(`
		INSERT INTO assignment_evaluations (submission_id, ai_score, max_score, percentage, strengths, weaknesses, missing_concepts, suggestions, teacher_feedback, evaluated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, '', now())
		ON CONFLICT (submission_id) DO UPDATE SET
			ai_score = EXCLUDED.ai_score, max_score = EXCLUDED.max_score, percentage = EXCLUDED.percentage,
			strengths = EXCLUDED.strengths, weaknesses = EXCLUDED.weaknesses, missing_concepts = EXCLUDED.missing_concepts,
			suggestions = EXCLUDED.suggestions, evaluated_at = now()`,
		submissionID, aiScore, maxScore, percentage, strengthsJSON, weaknessesJSON, missingJSON, suggestions,
	)
	if err != nil {
		return err
	}

	if _, err := tx.Exec(`UPDATE assignment_submissions SET status = 'evaluated', updated_at = now() WHERE id = $1`, submissionID); err != nil {
		return err
	}

	return tx.Commit()
}

// GetEvaluationBySubmission - fixed: teacher_feedback (and a couple other
// nullable-in-practice columns) are wrapped in COALESCE so a NULL there
// (the normal case before a teacher ever reviews) no longer makes the
// whole Scan fail and silently drop the entire evaluation from the API
// response - that was the actual bug behind "Evaluation hasn't come
// through yet" even though the row existed in the database all along.
func (r *Repository) GetEvaluationBySubmission(submissionID int) (*Evaluation, error) {
	var e Evaluation
	var strengthsRaw, weaknessesRaw, missingRaw []byte
	err := r.db.QueryRow(`
		SELECT id, submission_id, ai_score, max_score, percentage, strengths, weaknesses, missing_concepts,
		       COALESCE(suggestions, ''), teacher_override_score, COALESCE(teacher_feedback, ''), reviewed_by_teacher, evaluated_at
		FROM assignment_evaluations WHERE submission_id = $1`, submissionID,
	).Scan(&e.ID, &e.SubmissionID, &e.AIScore, &e.MaxScore, &e.Percentage, &strengthsRaw, &weaknessesRaw, &missingRaw,
		&e.Suggestions, &e.TeacherOverrideScore, &e.TeacherFeedback, &e.ReviewedByTeacher, &e.EvaluatedAt)
	if err != nil {
		return nil, err
	}
	if len(strengthsRaw) > 0 {
		_ = json.Unmarshal(strengthsRaw, &e.Strengths)
	}
	if len(weaknessesRaw) > 0 {
		_ = json.Unmarshal(weaknessesRaw, &e.Weaknesses)
	}
	if len(missingRaw) > 0 {
		_ = json.Unmarshal(missingRaw, &e.MissingConcepts)
	}
	return &e, nil
}

// SaveTeacherReview records a teacher's override score/feedback and moves
// the submission to 'returned'.
//
// BUG FIX: same missing-transaction issue as SaveAIEvaluation above -
// these were two independent Exec calls; a failure on the second left
// the evaluation marked reviewed but the submission stuck on its old
// status.
func (r *Repository) SaveTeacherReview(submissionID, teacherID int, overrideScore *int, feedback string) error {
	var assignmentID int
	if err := r.db.QueryRow(`SELECT assignment_id FROM assignment_submissions WHERE id = $1`, submissionID).Scan(&assignmentID); err != nil {
		if err == sql.ErrNoRows {
			return ErrNotFound
		}
		return err
	}
	if err := r.checkOwnership(assignmentID, teacherID); err != nil {
		return err
	}

	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec(`
		UPDATE assignment_evaluations SET
			teacher_override_score = $1, teacher_feedback = $2, reviewed_by_teacher = true, reviewed_at = now()
		WHERE submission_id = $3`,
		overrideScore, feedback, submissionID,
	)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(`UPDATE assignment_submissions SET status = 'returned', updated_at = now() WHERE id = $1`, submissionID); err != nil {
		return err
	}

	return tx.Commit()
}

// --- Analytics ---

func (r *Repository) GetAnalytics(teacherID *int) (*AnalyticsOverview, error) {
	overview := &AnalyticsOverview{}

	teacherFilter := ""
	args := []interface{}{}
	if teacherID != nil {
		teacherFilter = "WHERE a.teacher_id = $1"
		args = append(args, *teacherID)
	}

	err := r.db.QueryRow(`
		SELECT COUNT(*), COALESCE(SUM(CASE WHEN a.status = 'published' THEN 1 ELSE 0 END), 0)
		FROM assignments a `+teacherFilter, args...,
	).Scan(&overview.TotalAssignments, &overview.PublishedAssignments)
	if err != nil {
		return nil, err
	}

	subFilter := ""
	if teacherID != nil {
		subFilter = "WHERE a.teacher_id = $1"
	}
	err = r.db.QueryRow(`
		SELECT COUNT(sub.*), COALESCE(SUM(CASE WHEN sub.status = 'evaluated' OR sub.status = 'returned' THEN 1 ELSE 0 END), 0)
		FROM assignment_submissions sub
		JOIN assignments a ON a.id = sub.assignment_id
		`+subFilter, args...,
	).Scan(&overview.TotalSubmissions, &overview.EvaluatedSubmissions)
	if err != nil {
		return nil, err
	}

	avgFilter := ""
	if teacherID != nil {
		avgFilter = "WHERE a.teacher_id = $1"
	}
	var avgPct sql.NullFloat64
	err = r.db.QueryRow(`
		SELECT AVG(ev.percentage)
		FROM assignment_evaluations ev
		JOIN assignment_submissions sub ON sub.id = ev.submission_id
		JOIN assignments a ON a.id = sub.assignment_id
		`+avgFilter, args...,
	).Scan(&avgPct)
	if err != nil {
		return nil, err
	}
	if avgPct.Valid {
		overview.AverageScorePercent = avgPct.Float64
	}

	return overview, nil
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/assignment/repository.go"), $content_internal_assignment_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/assignment/repository.go" -ForegroundColor Green

# --- internal/assignment/service.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/assignment") | Out-Null
$content_internal_assignment_service_go = @'
package assignment

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"ai-tutor-backend/internal/ai"
	"ai-tutor-backend/internal/badge"
	"ai-tutor-backend/internal/streak"
	"ai-tutor-backend/internal/subjects"
	"ai-tutor-backend/internal/xp"
)

type Service struct {
	repo         *Repository
	subjectsRepo *subjects.Repository
	groqClient   *ai.GroqClient
	streakSvc    *streak.Service
	badgeSvc     *badge.Service
	xpSvc        *xp.Service
}

func NewService(repo *Repository, subjectsRepo *subjects.Repository, groqClient *ai.GroqClient, streakSvc *streak.Service, badgeSvc *badge.Service, xpSvc *xp.Service) *Service {
	return &Service{repo: repo, subjectsRepo: subjectsRepo, groqClient: groqClient, streakSvc: streakSvc, badgeSvc: badgeSvc, xpSvc: xpSvc}
}

// --- Teacher: CRUD ---

func (s *Service) CreateAssignment(teacherID int, req CreateAssignmentRequest) (int, error) {
	return s.repo.CreateAssignment(teacherID, req)
}

func (s *Service) UpdateAssignment(assignmentID, teacherID int, req UpdateAssignmentRequest) error {
	return s.repo.UpdateAssignment(assignmentID, teacherID, req)
}

func (s *Service) DeleteAssignment(assignmentID, teacherID int) error {
	return s.repo.DeleteAssignment(assignmentID, teacherID)
}

func (s *Service) Publish(assignmentID, teacherID int) error {
	return s.repo.SetStatus(assignmentID, teacherID, StatusPublished)
}

func (s *Service) Unpublish(assignmentID, teacherID int) error {
	hasSubs, err := s.repo.HasSubmissions(assignmentID)
	if err != nil {
		return err
	}
	if hasSubs {
		return ErrHasSubmissions
	}
	return s.repo.SetStatus(assignmentID, teacherID, StatusUnpublished)
}

func (s *Service) Close(assignmentID, teacherID int) error {
	return s.repo.SetStatus(assignmentID, teacherID, StatusClosed)
}

func (s *Service) Archive(assignmentID, teacherID int) error {
	return s.repo.SetStatus(assignmentID, teacherID, StatusArchived)
}

func (s *Service) GetByID(assignmentID int) (*Assignment, error) {
	return s.repo.GetByID(assignmentID)
}

func (s *Service) ListForTeacher(teacherID int) ([]Assignment, error) {
	return s.repo.ListForTeacher(teacherID)
}

func (s *Service) ListPublishedForSubject(subjectID, studentID int) ([]Assignment, error) {
	return s.repo.ListPublishedForSubject(subjectID, studentID)
}

func (s *Service) ListPublishedForStudent(studentID int) ([]Assignment, error) {
	return s.repo.ListPublishedForStudent(studentID)
}

func (s *Service) ListAllForAdmin() ([]Assignment, error) {
	return s.repo.ListAllForAdmin()
}

func (s *Service) GetAnalytics(teacherID *int) (*AnalyticsOverview, error) {
	return s.repo.GetAnalytics(teacherID)
}

// --- AI Assignment Generator (draft only - teacher edits before creating) ---

func (s *Service) GenerateAssignment(ctx context.Context, req GenerateAssignmentRequest) (*GeneratedAssignmentDraft, error) {
	subject, err := s.subjectsRepo.FindByID(0, req.SubjectID)
	if err != nil {
		return nil, err
	}

	difficulty := req.Difficulty
	if difficulty == "" {
		difficulty = "medium"
	}

	systemPrompt := "You are an expert curriculum designer. You output ONLY raw JSON - no markdown code fences, no preamble."
	userPrompt := fmt.Sprintf(`Design an open-ended written assignment about "%s" for the subject "%s", at %s difficulty.

Return ONLY a JSON object with exactly this shape:
{
  "title": "a short, specific assignment title",
  "description": "1-2 sentences describing what the assignment covers",
  "instructions": "clear step-by-step instructions for what the student should write/answer, 3-6 sentences",
  "estimated_minutes": 30
}

The assignment should require a written explanation (not multiple choice) - something an AI can meaningfully evaluate for concept understanding, completeness, and clarity. Output nothing but the JSON object.`, req.Topic, subject.Name, difficulty)

	messages := []ai.ChatCompletionMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	raw, err := s.groqClient.Chat(ctx, messages)
	if err != nil {
		return nil, err
	}

	clean := cleanJSONFence(raw)
	var draft GeneratedAssignmentDraft
	if err := json.Unmarshal([]byte(clean), &draft); err != nil {
		return nil, fmt.Errorf("invalid JSON from Groq: %w", err)
	}
	return &draft, nil
}

func cleanJSONFence(raw string) string {
	clean := strings.TrimSpace(raw)
	clean = strings.TrimPrefix(clean, "```json")
	clean = strings.TrimPrefix(clean, "```")
	clean = strings.TrimSuffix(clean, "```")
	return strings.TrimSpace(clean)
}

// --- Student: submission + AI evaluation ---

// SaveDraft persists a student's in-progress answer.
//
// BUG FIX: this used to call UpsertDraft directly with no check at all -
// unlike Submit (below), which correctly requires the assignment to be
// published before accepting anything. A student could save draft text
// against an assignment that was still in draft (not yet visible to
// them through any normal listing, but guessable/bookmarkable by id),
// already closed, or archived. Now mirrors Submit's gate. (UpsertDraft
// also independently guards against the already-submitted case via its
// own RowsAffected check - see repository.go.)
func (s *Service) SaveDraft(assignmentID, studentID int, text string) error {
	a, err := s.repo.GetByID(assignmentID)
	if err != nil {
		return err
	}
	if a.Status != StatusPublished {
		return ErrAssignmentNotOpen
	}
	return s.repo.UpsertDraft(assignmentID, studentID, text)
}

var ErrAssignmentNotOpen = fmt.Errorf("this assignment is no longer accepting submissions")

func (s *Service) Submit(ctx context.Context, assignmentID, studentID int, text string) (*Submission, error) {
	assignmentDetail, err := s.repo.GetByID(assignmentID)
	if err != nil {
		return nil, err
	}
	if assignmentDetail.Status != StatusPublished {
		return nil, ErrAssignmentNotOpen
	}

	submissionID, err := s.repo.SubmitFinal(assignmentID, studentID, text)
	if err != nil {
		return nil, err
	}

	if err := s.evaluateWithAI(ctx, submissionID, assignmentDetail, text); err != nil {
		log.Printf("[assignment] AI evaluation failed for submission %d: %v", submissionID, err)
	} else {
		_ = s.streakSvc.RecordActivity(studentID) // best-effort
		go s.xpSvc.OnStudyActivity(studentID)
	}
	go s.badgeSvc.CheckAndAwardBadges(studentID)
	go s.xpSvc.AwardHomeworkSubmission(studentID, submissionID)

	return s.repo.GetSubmissionByID(submissionID)
}

func (s *Service) RetryEvaluation(ctx context.Context, submissionID, studentID int) (*Submission, error) {
	sub, err := s.repo.GetSubmissionByID(submissionID)
	if err != nil {
		return nil, err
	}
	if sub.StudentID != studentID {
		return nil, ErrForbidden
	}

	assignmentDetail, err := s.repo.GetByID(sub.AssignmentID)
	if err != nil {
		return nil, err
	}

	if err := s.evaluateWithAI(ctx, submissionID, assignmentDetail, sub.SubmissionText); err != nil {
		log.Printf("[assignment] AI evaluation retry failed for submission %d: %v", submissionID, err)
		return nil, err
	}
	_ = s.streakSvc.RecordActivity(studentID) // best-effort

	return s.repo.GetSubmissionByID(submissionID)
}

func (s *Service) evaluateWithAI(ctx context.Context, submissionID int, a *Assignment, submissionText string) error {
	systemPrompt := "You are an expert teacher grading a student's written assignment answer. You output ONLY raw JSON - no markdown code fences, no preamble."
	userPrompt := fmt.Sprintf(`Assignment title: "%s"
Instructions given to the student: "%s"
Maximum marks: %d

Student's submitted answer:
"""
%s
"""

Evaluate this answer and return ONLY a JSON object with exactly this shape:
{
  "score": 7,
  "strengths": ["short point", "short point"],
  "weaknesses": ["short point", "short point"],
  "missing_concepts": ["concept the answer should have covered but didn't"],
  "suggestions": "1-3 sentences of concrete, encouraging advice for improvement"
}

"score" is an integer from 0 to %d based on concept accuracy, completeness, and clarity. Be fair but rigorous - do not give full marks unless the answer genuinely deserves it. Output nothing but the JSON object.`,
		a.Title, a.Instructions, a.MaxMarks, submissionText, a.MaxMarks)

	messages := []ai.ChatCompletionMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	raw, err := s.groqClient.Chat(ctx, messages)
	if err != nil {
		return err
	}

	clean := cleanJSONFence(raw)
	var result struct {
		Score           int      `json:"score"`
		Strengths       []string `json:"strengths"`
		Weaknesses      []string `json:"weaknesses"`
		MissingConcepts []string `json:"missing_concepts"`
		Suggestions     string   `json:"suggestions"`
	}
	if err := json.Unmarshal([]byte(clean), &result); err != nil {
		return fmt.Errorf("invalid JSON from Groq: %w", err)
	}

	// QA fix ("Clamp AI score within valid marks"): the prompt asks Groq
	// for an integer from 0 to MaxMarks, but nothing enforced that - an
	// LLM can (and occasionally does) return a score outside that range,
	// which then produced a nonsensical percentage (e.g. >100%, or
	// negative) shown directly to the student. Clamp it to the valid
	// range before it's ever saved.
	score := result.Score
	if score < 0 {
		score = 0
	}
	if score > a.MaxMarks {
		score = a.MaxMarks
	}

	return s.repo.SaveAIEvaluation(submissionID, score, a.MaxMarks, result.Strengths, result.Weaknesses, result.MissingConcepts, result.Suggestions)
}

func (s *Service) GetMySubmission(assignmentID, studentID int) (*Submission, error) {
	return s.repo.GetSubmissionByAssignmentAndStudent(assignmentID, studentID)
}

// --- Teacher: review queue ---

func (s *Service) ListSubmissionsForAssignment(assignmentID, teacherID int) ([]Submission, error) {
	return s.repo.ListSubmissionsForAssignment(assignmentID, teacherID)
}

func (s *Service) TeacherReview(submissionID, teacherID int, req TeacherReviewRequest) error {
	return s.repo.SaveTeacherReview(submissionID, teacherID, req.OverrideScore, req.Feedback)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/assignment/service.go"), $content_internal_assignment_service_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/assignment/service.go" -ForegroundColor Green

# --- internal/assignment/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/assignment") | Out-Null
$content_internal_assignment_handler_go = @'
package assignment

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func respondForServiceError(c *gin.Context, err error, fallbackMsg string) {
	switch {
	case errors.Is(err, ErrNotFound):
		utils.RespondError(c, http.StatusNotFound, "Assignment not found")
	case errors.Is(err, ErrForbidden):
		utils.RespondError(c, http.StatusForbidden, "You can only manage assignments you created")
	case errors.Is(err, ErrCannotDelete):
		utils.RespondError(c, http.StatusConflict, "Published assignments must be archived before they can be deleted")
	case errors.Is(err, ErrHasSubmissions):
		utils.RespondError(c, http.StatusConflict, "Cannot unpublish - students have already submitted. Close or Archive it instead.")
	case errors.Is(err, ErrAssignmentNotOpen):
		utils.RespondError(c, http.StatusConflict, "This assignment is no longer accepting submissions")
	case errors.Is(err, ErrInvalidDate):
		utils.RespondError(c, http.StatusBadRequest, "start_date/due_date must be a valid ISO8601 timestamp")
	default:
		utils.RespondError(c, http.StatusInternalServerError, fallbackMsg)
	}
}

// --- Teacher: CRUD ---

// Create handles POST /api/assignments.
func (h *Handler) Create(c *gin.Context) {
	var req CreateAssignmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "subject_id and title are required")
		return
	}
	teacherID := c.GetInt("user_id")

	id, err := h.service.CreateAssignment(teacherID, req)
	if err != nil {
		respondForServiceError(c, err, "Failed to create assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusCreated, "Assignment created", gin.H{"id": id})
}

// Update handles PUT /api/assignments/:id.
func (h *Handler) Update(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	var req UpdateAssignmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	teacherID := c.GetInt("user_id")

	if err := h.service.UpdateAssignment(id, teacherID, req); err != nil {
		respondForServiceError(c, err, "Failed to update assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment updated", nil)
}

// Delete handles DELETE /api/assignments/:id.
func (h *Handler) Delete(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	teacherID := c.GetInt("user_id")

	if err := h.service.DeleteAssignment(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to delete assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment deleted", nil)
}

// Publish handles POST /api/assignments/:id/publish.
func (h *Handler) Publish(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.Publish(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to publish assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment published", nil)
}

// Unpublish handles POST /api/assignments/:id/unpublish.
func (h *Handler) Unpublish(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.Unpublish(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to unpublish assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment unpublished", nil)
}

// Close handles POST /api/assignments/:id/close.
func (h *Handler) Close(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.Close(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to close assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment closed", nil)
}

// Archive handles POST /api/assignments/:id/archive.
func (h *Handler) Archive(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.Archive(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to archive assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment archived", nil)
}

// GenerateAI handles POST /api/assignments/generate-ai.
func (h *Handler) GenerateAI(c *gin.Context) {
	var req GenerateAssignmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "subject_id and topic are required")
		return
	}

	draft, err := h.service.GenerateAssignment(c.Request.Context(), req)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to generate assignment. Please try again.")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment draft generated", draft)
}

// ListMine handles GET /api/assignments/mine (teacher's own assignments).
func (h *Handler) ListMine(c *gin.Context) {
	teacherID := c.GetInt("user_id")
	list, err := h.service.ListForTeacher(teacherID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load assignments")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignments fetched", list)
}

// GetByID handles GET /api/assignments/:id.
func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	a, err := h.service.GetByID(id)
	if err != nil {
		respondForServiceError(c, err, "Failed to load assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment fetched", a)
}

// ListForSubject handles GET /api/subjects/:id/assignments.
func (h *Handler) ListForSubject(c *gin.Context) {
	subjectID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid subject id")
		return
	}
	studentID := c.GetInt("user_id")
	list, err := h.service.ListPublishedForSubject(subjectID, studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load assignments")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignments fetched", list)
}

// ListForStudent handles GET /api/assignments/for-student - every
// published assignment across every subject the student is enrolled in.
func (h *Handler) ListForStudent(c *gin.Context) {
	studentID := c.GetInt("user_id")
	list, err := h.service.ListPublishedForStudent(studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load assignments")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignments fetched", list)
}

// TeacherAnalytics handles GET /api/assignments/analytics (teacher-scoped).
func (h *Handler) TeacherAnalytics(c *gin.Context) {
	teacherID := c.GetInt("user_id")
	overview, err := h.service.GetAnalytics(&teacherID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load analytics")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Analytics fetched", overview)
}

// --- Student: submissions ---

// SaveDraft handles POST /api/assignments/:id/draft.
func (h *Handler) SaveDraft(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	var req SaveDraftRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	studentID := c.GetInt("user_id")

	if err := h.service.SaveDraft(id, studentID, req.SubmissionText); err != nil {
		respondForServiceError(c, err, "Failed to save draft")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Draft saved", nil)
}

// Submit handles POST /api/assignments/:id/submit.
func (h *Handler) Submit(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	var req SubmitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "submission_text is required")
		return
	}
	studentID := c.GetInt("user_id")

	submission, err := h.service.Submit(c.Request.Context(), id, studentID, req.SubmissionText)
	if err != nil {
		respondForServiceError(c, err, "Failed to submit assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment submitted", submission)
}

// GetMySubmission handles GET /api/assignments/:id/my-submission.
func (h *Handler) GetMySubmission(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	studentID := c.GetInt("user_id")

	submission, err := h.service.GetMySubmission(id, studentID)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			utils.RespondSuccess(c, http.StatusOK, "No submission yet", nil)
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load submission")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Submission fetched", submission)
}

// RetryEvaluation handles POST /api/assignments/submissions/:id/retry-evaluation.
func (h *Handler) RetryEvaluation(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid submission id")
		return
	}
	studentID := c.GetInt("user_id")

	submission, err := h.service.RetryEvaluation(c.Request.Context(), id, studentID)
	if err != nil {
		respondForServiceError(c, err, "Evaluation failed again. Please try once more in a moment.")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Evaluation complete", submission)
}

// --- Teacher: review queue ---

// ListSubmissions handles GET /api/assignments/:id/submissions.
func (h *Handler) ListSubmissions(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	teacherID := c.GetInt("user_id")

	list, err := h.service.ListSubmissionsForAssignment(id, teacherID)
	if err != nil {
		respondForServiceError(c, err, "Failed to load submissions")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Submissions fetched", list)
}

// ReviewSubmission handles POST /api/assignments/submissions/:id/review.
func (h *Handler) ReviewSubmission(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid submission id")
		return
	}
	var req TeacherReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	teacherID := c.GetInt("user_id")

	if err := h.service.TeacherReview(id, teacherID, req); err != nil {
		respondForServiceError(c, err, "Failed to save review")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Review saved", nil)
}

// --- Admin: monitoring ---

// ListAllForAdmin handles GET /api/admin/assignments.
func (h *Handler) ListAllForAdmin(c *gin.Context) {
	list, err := h.service.ListAllForAdmin()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load assignments")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignments fetched", list)
}

// AdminAnalytics handles GET /api/admin/assignments/analytics.
func (h *Handler) AdminAnalytics(c *gin.Context) {
	overview, err := h.service.GetAnalytics(nil)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load analytics")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Analytics fetched", overview)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/assignment/handler.go"), $content_internal_assignment_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/assignment/handler.go" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Yellow
Write-Host "  1. go build ./... to sanity check"
Write-Host "  2. cd .. ; docker compose build --no-cache backend"
Write-Host "  3. docker compose up -d --force-recreate backend"
Write-Host "  4. docker logs ai_tutor_backend --tail 15"