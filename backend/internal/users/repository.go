package users

import (
	"database/sql"
	"errors"

	"github.com/lib/pq"
)

var ErrEmailAlreadyExists = errors.New("email already registered")

// pqUniqueViolation is Postgres's SQLSTATE code for a unique-constraint
// violation - same constant/pattern as auth/repository.go.
const pqUniqueViolation = "23505"

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) ListAll() ([]User, error) {
	rows, err := r.db.Query(`SELECT id, name, email, role, created_at FROM users ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.Role, &u.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, u)
	}
	return result, nil
}

func (r *Repository) UpdateName(id int, name string) error {
	_, err := r.db.Exec(`UPDATE users SET name = $1 WHERE id = $2`, name, id)
	return err
}

// UpdateNameAndEmail updates a user's profile name/email.
//
// QA fix ("TOCTOU on email uniqueness; raw 500 instead of translated
// 409"): the previous version did a SELECT-then-UPDATE check - two
// concurrent updates to the same new email could both pass the SELECT
// before either UPDATE ran, and if the UPDATE itself then hit the DB's
// UNIQUE constraint (users_email_unique_idx, migration 026), the raw
// Postgres error propagated straight up as an unhandled 500 instead of
// the intended "email already in use" conflict. Now the UPDATE is
// attempted directly and a unique-violation is translated into
// ErrEmailAlreadyExists - race-proof, since Postgres itself serializes
// the conflicting updates and only lets one succeed.
func (r *Repository) UpdateNameAndEmail(id int, name, email string) error {
	_, err := r.db.Exec(`UPDATE users SET name = $1, email = $2 WHERE id = $3`, name, email, id)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == pqUniqueViolation {
			return ErrEmailAlreadyExists
		}
		return err
	}
	return nil
}

func (r *Repository) GetPasswordHash(id int) (string, error) {
	var hash string
	err := r.db.QueryRow(`SELECT password_hash FROM users WHERE id = $1`, id).Scan(&hash)
	return hash, err
}

func (r *Repository) UpdatePasswordHash(id int, newHash string) error {
	_, err := r.db.Exec(`UPDATE users SET password_hash = $1 WHERE id = $2`, newHash, id)
	return err
}

// --- Class/Section (admin-only, students-only, Leaderboard use only) ---

var ErrNotAStudent = errors.New("class and section can only be assigned to students")

// AssignClassSection sets a student's class/section - rejects if the
// target user isn't actually a student (these fields are meaningless for
// teachers/admins per the requirement).
func (r *Repository) AssignClassSection(studentID int, class, section string) error {
	var role string
	if err := r.db.QueryRow(`SELECT role FROM users WHERE id = $1`, studentID).Scan(&role); err != nil {
		return err
	}
	if role != "student" {
		return ErrNotAStudent
	}
	_, err := r.db.Exec(`UPDATE users SET class = $1, section = $2 WHERE id = $3`, class, section, studentID)
	return err
}

// GetClassSection is used by the Leaderboard to enforce "students only
// see their own class" - not exposed via any student-facing endpoint.
func (r *Repository) GetClassSection(studentID int) (class, section string, err error) {
	var classVal, sectionVal sql.NullString
	err = r.db.QueryRow(`SELECT class, section FROM users WHERE id = $1`, studentID).Scan(&classVal, &sectionVal)
	return classVal.String, sectionVal.String, err
}

// ListStudentsWithClassSection powers the admin's student-management
// list - so an admin can see who to assign a class/section to.
func (r *Repository) ListStudentsWithClassSection() ([]StudentWithClassSection, error) {
	rows, err := r.db.Query(`
		SELECT id, name, email, COALESCE(class, ''), COALESCE(section, '')
		FROM users WHERE role = 'student' ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []StudentWithClassSection
	for rows.Next() {
		var s StudentWithClassSection
		if err := rows.Scan(&s.ID, &s.Name, &s.Email, &s.Class, &s.Section); err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	return result, rows.Err()
}
