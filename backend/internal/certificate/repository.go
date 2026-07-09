package certificate

import (
	"database/sql"
	"errors"
	"fmt"
)

var ErrNotFound = errors.New("certificate not found")
var ErrAlreadyExists = errors.New("certificate already generated")
var ErrNotEligible = errors.New("student has not completed this course or has not passed")

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// HasCertificate checks the UNIQUE(student_id, subject_id) constraint
// ahead of time, so callers can show "Certificate already generated"
// instead of a raw DB conflict error.
func (r *Repository) HasCertificate(studentID, subjectID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM certificates WHERE student_id = $1 AND subject_id = $2)`, studentID, subjectID).Scan(&exists)
	return exists, err
}

// IsSubjectFullyCompleted - 100% of the subject's lessons completed by
// this student. A subject with zero lessons never counts as "completed"
// (there's nothing to certify).
func (r *Repository) IsSubjectFullyCompleted(studentID, subjectID int) (bool, error) {
	var totalLessons, completedLessons int
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons WHERE subject_id = $1`, subjectID).Scan(&totalLessons); err != nil {
		return false, err
	}
	if totalLessons == 0 {
		return false, nil
	}
	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM lesson_progress lp
		JOIN lessons l ON l.id = lp.lesson_id
		WHERE l.subject_id = $1 AND lp.user_id = $2`, subjectID, studentID).Scan(&completedLessons)
	if err != nil {
		return false, err
	}
	return completedLessons == totalLessons, nil
}

// GetFinalScore - the "final assessment" for this app is the student's
// average score across every quiz attempt taken in this subject (there's
// no separate dedicated "final exam" entity). Returns (score, hasAny).
func (r *Repository) GetFinalScore(studentID, subjectID int) (float64, bool, error) {
	var avg sql.NullFloat64
	err := r.db.QueryRow(`
		SELECT AVG(score_percent) FROM quiz_attempts
		WHERE user_id = $1 AND subject_id = $2`, studentID, subjectID).Scan(&avg)
	if err != nil {
		return 0, false, err
	}
	if !avg.Valid {
		return 0, false, nil
	}
	return avg.Float64, true, nil
}

// GetCompletionDate - the date the student finished their LAST lesson in
// this subject (i.e. the day they crossed 100%).
func (r *Repository) GetCompletionDate(studentID, subjectID int) (string, error) {
	var date string
	err := r.db.QueryRow(`
		SELECT to_char(MAX(lp.completed_at), 'YYYY-MM-DD') FROM lesson_progress lp
		JOIN lessons l ON l.id = lp.lesson_id
		WHERE l.subject_id = $1 AND lp.user_id = $2`, subjectID, studentID).Scan(&date)
	return date, err
}

// GetCourseAndSubjectName - course_categories is "the course", subjects
// is the specific subject within it.
func (r *Repository) GetCourseAndSubjectName(subjectID int) (courseName, subjectName string, err error) {
	err = r.db.QueryRow(`
		SELECT cc.name, s.name FROM subjects s
		JOIN course_categories cc ON cc.id = s.category_id
		WHERE s.id = $1`, subjectID).Scan(&courseName, &subjectName)
	return courseName, subjectName, err
}

// GetInstructorName - subjects/lessons have no direct teacher_id, so the
// "instructor" is inferred as whichever teacher has been most active for
// this subject: most live classes taught, falling back to most
// assignments created, falling back to a generic label.
func (r *Repository) GetInstructorName(subjectID int) (string, error) {
	var name sql.NullString
	err := r.db.QueryRow(`
		SELECT u.name FROM live_classes lc
		JOIN users u ON u.id = lc.teacher_id
		WHERE lc.subject_id = $1
		GROUP BY u.name
		ORDER BY COUNT(*) DESC
		LIMIT 1`, subjectID).Scan(&name)
	if err == nil && name.Valid {
		return name.String, nil
	}

	err = r.db.QueryRow(`
		SELECT u.name FROM assignments a
		JOIN assignment_targets t ON t.assignment_id = a.id AND t.target_type = 'subject'
		JOIN users u ON u.id = a.teacher_id
		WHERE t.target_id = $1
		GROUP BY u.name
		ORDER BY COUNT(*) DESC
		LIMIT 1`, subjectID).Scan(&name)
	if err == nil && name.Valid {
		return name.String, nil
	}

	return "AI Tutor Faculty", nil
}

// Create inserts a new certificate - the UNIQUE(student_id, subject_id)
// constraint is the real guard against duplicates; HasCertificate above
// is just for a friendlier pre-check.
func (r *Repository) Create(studentID, subjectID int, courseName, subjectName, instructorName string, finalScore float64, completionDate string) (*Certificate, error) {
	code := fmt.Sprintf("AITUTOR-CERT-%d-%d", studentID, subjectID)
	grade := gradeForScore(finalScore)

	var c Certificate
	err := r.db.QueryRow(`
		INSERT INTO certificates (certificate_code, student_id, subject_id, course_name, subject_name, instructor_name, final_score, grade, completion_date)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (student_id, subject_id) DO NOTHING
		RETURNING id, certificate_code, student_id, subject_id, course_name, subject_name, instructor_name, final_score, grade, completion_date::text, issue_date`,
		code, studentID, subjectID, courseName, subjectName, instructorName, finalScore, grade, completionDate,
	).Scan(&c.ID, &c.CertificateCode, &c.StudentID, &c.SubjectID, &c.CourseName, &c.SubjectName, &c.InstructorName, &c.FinalScore, &c.Grade, &c.CompletionDate, &c.IssueDate)
	if err == sql.ErrNoRows {
		return nil, ErrAlreadyExists
	}
	if err != nil {
		return nil, err
	}
	return &c, nil
}

const certSelect = `
	SELECT c.id, c.certificate_code, c.student_id, u.name, c.subject_id, c.course_name, c.subject_name, c.instructor_name, c.final_score, c.grade, c.completion_date::text, c.issue_date
	FROM certificates c
	JOIN users u ON u.id = c.student_id
`

func scanCertificate(row interface{ Scan(...any) error }) (Certificate, error) {
	var c Certificate
	err := row.Scan(&c.ID, &c.CertificateCode, &c.StudentID, &c.StudentName, &c.SubjectID, &c.CourseName, &c.SubjectName, &c.InstructorName, &c.FinalScore, &c.Grade, &c.CompletionDate, &c.IssueDate)
	return c, err
}

func (r *Repository) GetByID(id int) (*Certificate, error) {
	row := r.db.QueryRow(certSelect+` WHERE c.id = $1`, id)
	c, err := scanCertificate(row)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *Repository) ListForStudent(studentID int) ([]Certificate, error) {
	rows, err := r.db.Query(certSelect+` WHERE c.student_id = $1 ORDER BY c.issue_date DESC`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanCertRows(rows)
}

// ListForTeacher - certificates for students in subjects this teacher
// has been active in (same "most active instructor" subjects, via
// live_classes or assignments they created).
func (r *Repository) ListForTeacher(teacherID int) ([]Certificate, error) {
	rows, err := r.db.Query(certSelect+`
		WHERE c.subject_id IN (
			SELECT DISTINCT subject_id FROM live_classes WHERE teacher_id = $1 AND subject_id IS NOT NULL
			UNION
			SELECT DISTINCT t.target_id FROM assignments a
			JOIN assignment_targets t ON t.assignment_id = a.id AND t.target_type = 'subject'
			WHERE a.teacher_id = $1
		)
		ORDER BY c.issue_date DESC`, teacherID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanCertRows(rows)
}

func (r *Repository) ListAll() ([]Certificate, error) {
	rows, err := r.db.Query(certSelect + ` ORDER BY c.issue_date DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanCertRows(rows)
}

func scanCertRows(rows *sql.Rows) ([]Certificate, error) {
	var result []Certificate
	for rows.Next() {
		c, err := scanCertificate(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, c)
	}
	return result, rows.Err()
}
