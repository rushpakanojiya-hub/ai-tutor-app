package users

import (
	"database/sql"
	"errors"

	"github.com/lib/pq"
)

var ErrEmailAlreadyExists = errors.New("email already registered")
var ErrUserNotFound = errors.New("user not found")

// postgres unique_violation error code.
const pqUniqueViolation = "23505"

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// ListAll returns every user (admin/debug use).
//
// BUG FIX: was missing a rows.Err() check after the scan loop - a
// connection error mid-iteration would silently return a truncated list
// instead of an error.
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
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

func (r *Repository) UpdateName(id int, name string) error {
	res, err := r.db.Exec(`UPDATE users SET name = $1 WHERE id = $2`, name, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrUserNotFound
	}
	return nil
}

// UpdateNameAndEmail updates a user's name/email.
//
// BUG FIX (race condition): the previous version only did a SELECT-then-
// UPDATE existence check for the new email - the exact
// time-of-check-to-time-of-use gap already identified and fixed for
// registration (see auth.Repository.CreateUser / migration 026's
// users_email_unique_idx). Two concurrent profile updates to the same
// new email could both pass the pre-check before either UPDATEs. The
// pre-check is kept as a fast/friendly path, but the UPDATE's own
// unique-constraint violation is now the actual guarantee, translated
// into ErrEmailAlreadyExists - race-proof regardless of timing.
func (r *Repository) UpdateNameAndEmail(id int, name, email string) error {
	var existingID int
	err := r.db.QueryRow(`SELECT id FROM users WHERE email = $1`, email).Scan(&existingID)
	if err == nil && existingID != id {
		return ErrEmailAlreadyExists
	}
	if err != nil && err != sql.ErrNoRows {
		return err
	}

	res, err := r.db.Exec(`UPDATE users SET name = $1, email = $2 WHERE id = $3`, name, email, id)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == pqUniqueViolation {
			return ErrEmailAlreadyExists
		}
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrUserNotFound
	}
	return nil
}

func (r *Repository) GetPasswordHash(id int) (string, error) {
	var hash string
	err := r.db.QueryRow(`SELECT password_hash FROM users WHERE id = $1`, id).Scan(&hash)
	if err == sql.ErrNoRows {
		return "", ErrUserNotFound
	}
	return hash, err
}

func (r *Repository) UpdatePasswordHash(id int, newHash string) error {
	res, err := r.db.Exec(`UPDATE users SET password_hash = $1 WHERE id = $2`, newHash, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrUserNotFound
	}
	return nil
}

// --- Class/Section (admin-only, students-only, Leaderboard use only) ---

var ErrNotAStudent = errors.New("class and section can only be assigned to students")

// AssignClassSection sets a student's class/section - rejects if the
// target user isn't actually a student (these fields are meaningless for
// teachers/admins per the requirement).
func (r *Repository) AssignClassSection(studentID int, class, section string) error {
	var role string
	if err := r.db.QueryRow(`SELECT role FROM users WHERE id = $1`, studentID).Scan(&role); err != nil {
		if err == sql.ErrNoRows {
			return ErrUserNotFound
		}
		return err
	}
	if role != "student" {
		return ErrNotAStudent
	}
	res, err := r.db.Exec(`UPDATE users SET class = $1, section = $2 WHERE id = $3`, class, section, studentID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrUserNotFound
	}
	return nil
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
