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

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func parseOptionalTime(s string) *time.Time {
	if s == "" {
		return nil
	}
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return nil
	}
	return &t
}

// CreateAssignment inserts the assignment and its subject target in one
// transaction.
func (r *Repository) CreateAssignment(teacherID int, req CreateAssignmentRequest) (int, error) {
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
		parseOptionalTime(req.StartDate), parseOptionalTime(req.DueDate), StatusDraft,
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

// checkOwnership verifies the assignment exists and belongs to teacherID.
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

// UpdateAssignment applies only the provided (non-nil) fields, after
// verifying ownership.
func (r *Repository) UpdateAssignment(assignmentID, teacherID int, req UpdateAssignmentRequest) error {
	if err := r.checkOwnership(assignmentID, teacherID); err != nil {
		return err
	}

	_, err := r.db.Exec(`
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
		parseOptionalTimePtr(req.StartDate), parseOptionalTimePtr(req.DueDate), assignmentID,
	)
	return err
}

func parseOptionalTimePtr(s *string) *time.Time {
	if s == nil {
		return nil
	}
	return parseOptionalTime(*s)
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

// HasSubmissions reports whether any student has submitted (or drafted)
// against this assignment - used to block Unpublish once real activity exists.
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

// assignmentSelectForStudent additionally selects that student's own
// submission status (or 'not_started' if none exists) - used only by the
// two student-facing list queries below. $N below is always the
// student_id parameter - callers must pass it as the query's last arg.
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

// ListPublishedForSubject returns published assignments targeting a
// subject - what students see on that subject's page. Only enrolled
// students see anything (see internal/enrollment - a student is enrolled
// automatically once they complete any lesson in the subject).
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

// ListPublishedForStudent returns every published assignment across every
// subject the student is enrolled in - powers the dedicated Assignments
// tab and the Home dashboard "New Assignment" card, so a student doesn't
// have to dig through Course -> Subject -> Lesson to find one.
// ListPublishedForStudent returns every published assignment across every
// subject - powers the dedicated Assignments tab and the Home dashboard
// "New Assignment" card. No enrollment restriction: every student can
// already see every subject's lessons in this app, so assignments follow
// the same open-access model.
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

// ListAllForAdmin returns every assignment platform-wide, for monitoring.
func (r *Repository) ListAllForAdmin() ([]Assignment, error) {
	rows, err := r.db.Query(assignmentSelect + ` ORDER BY a.created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanAssignmentRows(rows)
}

// GetTargetSubjectID returns the subject this assignment targets
// (Phase 1: always exactly one subject target).
func (r *Repository) GetTargetSubjectID(assignmentID int) (int, error) {
	var subjectID int
	err := r.db.QueryRow(`
		SELECT target_id FROM assignment_targets
		WHERE assignment_id = $1 AND target_type = 'subject' LIMIT 1`, assignmentID).Scan(&subjectID)
	return subjectID, err
}

// GetEnrolledStudentIDs returns every student enrolled in a subject - the
// fan-out list for "new assignment published" notifications.
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
	return ids, nil
}

// GetSubmissionStudentID is used to know who to notify after a teacher review.
func (r *Repository) GetSubmissionStudentID(submissionID int) (int, error) {
	var studentID int
	err := r.db.QueryRow(`SELECT student_id FROM assignment_submissions WHERE id = $1`, submissionID).Scan(&studentID)
	return studentID, err
}

// ListForStudent returns every published assignment across every subject
// the student is enrolled in, with their own submission status attached -
// so the student doesn't have to dig through Course -> Subject -> Lesson
// to find assignments (Home dashboard and a dedicated Assignments tab
// both use this).
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

	// Attach each assignment's status for THIS student (pending/submitted/evaluated/etc).
	for i := range assignments {
		var status sql.NullString
		_ = r.db.QueryRow(`SELECT status FROM assignment_submissions WHERE assignment_id = $1 AND student_id = $2`,
			assignments[i].ID, studentID).Scan(&status)
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

// UpsertDraft creates or updates a student's draft submission (one row
// per assignment+student, enforced by a UNIQUE constraint).
func (r *Repository) UpsertDraft(assignmentID, studentID int, text string) error {
	_, err := r.db.Exec(`
		INSERT INTO assignment_submissions (assignment_id, student_id, submission_text, status)
		VALUES ($1, $2, $3, 'draft')
		ON CONFLICT (assignment_id, student_id) DO UPDATE SET
			submission_text = EXCLUDED.submission_text,
			updated_at = now()
		WHERE assignment_submissions.status = 'draft'`,
		assignmentID, studentID, text,
	)
	return err
}

// SubmitFinal marks the submission as submitted (locking it in), text
// included, and returns its ID.
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

// ListSubmissionsForAssignment is for the teacher review queue -
// verifies the assignment belongs to teacherID first.
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
	return result, nil
}

// --- Evaluations ---

func (r *Repository) SaveAIEvaluation(submissionID, aiScore, maxScore int, strengths, weaknesses, missingConcepts []string, suggestions string) error {
	strengthsJSON, _ := json.Marshal(strengths)
	weaknessesJSON, _ := json.Marshal(weaknesses)
	missingJSON, _ := json.Marshal(missingConcepts)

	percentage := 0.0
	if maxScore > 0 {
		percentage = (float64(aiScore) / float64(maxScore)) * 100
	}

	_, err := r.db.Exec(`
		INSERT INTO assignment_evaluations (submission_id, ai_score, max_score, percentage, strengths, weaknesses, missing_concepts, suggestions, evaluated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now())
		ON CONFLICT (submission_id) DO UPDATE SET
			ai_score = EXCLUDED.ai_score, max_score = EXCLUDED.max_score, percentage = EXCLUDED.percentage,
			strengths = EXCLUDED.strengths, weaknesses = EXCLUDED.weaknesses, missing_concepts = EXCLUDED.missing_concepts,
			suggestions = EXCLUDED.suggestions, evaluated_at = now()`,
		submissionID, aiScore, maxScore, percentage, strengthsJSON, weaknessesJSON, missingJSON, suggestions,
	)
	if err != nil {
		return err
	}

	_, err = r.db.Exec(`UPDATE assignment_submissions SET status = 'evaluated', updated_at = now() WHERE id = $1`, submissionID)
	return err
}

func (r *Repository) GetEvaluationBySubmission(submissionID int) (*Evaluation, error) {
	var e Evaluation
	var strengthsRaw, weaknessesRaw, missingRaw []byte
	err := r.db.QueryRow(`
		SELECT id, submission_id, ai_score, max_score, percentage, strengths, weaknesses, missing_concepts,
		       suggestions, teacher_override_score, teacher_feedback, reviewed_by_teacher, evaluated_at
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

// SaveTeacherReview verifies the submission's assignment belongs to
// teacherID before allowing an override.
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

	_, err := r.db.Exec(`
		UPDATE assignment_evaluations SET
			teacher_override_score = $1, teacher_feedback = $2, reviewed_by_teacher = true, reviewed_at = now()
		WHERE submission_id = $3`,
		overrideScore, feedback, submissionID,
	)
	if err != nil {
		return err
	}
	_, err = r.db.Exec(`UPDATE assignment_submissions SET status = 'returned', updated_at = now() WHERE id = $1`, submissionID)
	return err
}

// --- Analytics (teacher scoped or platform-wide for admin) ---

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
