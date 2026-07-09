package users

import (
	"database/sql"
	"errors"
)

var ErrEmailAlreadyExists = errors.New("email already registered")

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

func (r *Repository) UpdateNameAndEmail(id int, name, email string) error {
	var existingID int
	err := r.db.QueryRow(`SELECT id FROM users WHERE email = $1`, email).Scan(&existingID)
	if err == nil && existingID != id {
		return ErrEmailAlreadyExists
	}
	if err != nil && err != sql.ErrNoRows {
		return err
	}

	_, err = r.db.Exec(`UPDATE users SET name = $1, email = $2 WHERE id = $3`, name, email, id)
	return err
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
