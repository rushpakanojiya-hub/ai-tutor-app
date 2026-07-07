// Package enrollment tracks which subjects a student is actively engaged
// with, so features that need "eligible students" (like assignment
// visibility) have something real to check against - not an
// all-or-nothing assumption.
//
// A student becomes enrolled in a subject automatically the first time
// they complete any lesson in it (see progress.Service). This is
// intentionally lightweight for Phase 1 - no explicit "Enroll" button
// yet, no un-enrollment, no batch/classroom grouping (those are reserved
// future extensions and need no schema change to this table).
package enrollment

import "database/sql"

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// EnsureEnrolled marks studentID as enrolled in subjectID. Idempotent.
func (r *Repository) EnsureEnrolled(studentID, subjectID int) error {
	_, err := r.db.Exec(`
		INSERT INTO subject_enrollments (student_id, subject_id)
		VALUES ($1, $2)
		ON CONFLICT (student_id, subject_id) DO NOTHING`,
		studentID, subjectID,
	)
	return err
}

func (r *Repository) IsEnrolled(studentID, subjectID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`
		SELECT EXISTS(SELECT 1 FROM subject_enrollments WHERE student_id = $1 AND subject_id = $2)`,
		studentID, subjectID,
	).Scan(&exists)
	return exists, err
}

func (r *Repository) CountEnrolled(subjectID int) (int, error) {
	var count int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM subject_enrollments WHERE subject_id = $1`, subjectID).Scan(&count)
	return count, err
}
