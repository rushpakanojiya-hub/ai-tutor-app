package auth

import (
	"database/sql"
	"errors"
)

// ErrUserNotFound is returned when no user matches the given lookup.
var ErrUserNotFound = errors.New("user not found")

// ErrEmailAlreadyExists is returned when registering with a duplicate email.
var ErrEmailAlreadyExists = errors.New("email already registered")

// Repository handles direct SQL access for the users table (auth context).
type Repository struct {
	db *sql.DB
}

// NewRepository builds an auth Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// CreateUser inserts a new user row (with the given status) and returns
// the generated ID.
func (r *Repository) CreateUser(name, email, passwordHash, role, status string) (int, error) {
	var exists bool
	checkQuery := `SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)`
	if err := r.db.QueryRow(checkQuery, email).Scan(&exists); err != nil {
		return 0, err
	}
	if exists {
		return 0, ErrEmailAlreadyExists
	}

	var id int
	insertQuery := `
		INSERT INTO users (name, email, password_hash, role, status)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`
	err := r.db.QueryRow(insertQuery, name, email, passwordHash, role, status).Scan(&id)
	if err != nil {
		return 0, err
	}
	return id, nil
}

// CreateTeacherProfile stores the extra application details a teacher
// submitted, alongside their (pending) user row.
func (r *Repository) CreateTeacherProfile(userID int, phone, qualification, experience, subjects, bio string) error {
	_, err := r.db.Exec(`
		INSERT INTO teacher_profiles (user_id, phone, qualification, experience, subjects, bio)
		VALUES ($1, $2, $3, $4, $5, $6)`,
		userID, phone, qualification, experience, subjects, bio,
	)
	return err
}

// FindByEmail returns the user matching the given email, or ErrUserNotFound.
func (r *Repository) FindByEmail(email string) (*User, error) {
	query := `
		SELECT id, name, email, password_hash, role, status, created_at
		FROM users
		WHERE email = $1
	`
	var u User
	err := r.db.QueryRow(query, email).Scan(&u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.Role, &u.Status, &u.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// FindByID returns the user matching the given primary key, or ErrUserNotFound.
func (r *Repository) FindByID(id int) (*User, error) {
	query := `
		SELECT id, name, email, password_hash, role, status, created_at
		FROM users
		WHERE id = $1
	`
	var u User
	err := r.db.QueryRow(query, id).Scan(&u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.Role, &u.Status, &u.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// ListTeacherApplications returns teacher accounts filtered by status
// (e.g. "pending"), for the admin approval queue.
func (r *Repository) ListTeacherApplications(status string) ([]TeacherApplication, error) {
	rows, err := r.db.Query(`
		SELECT u.id, u.name, u.email, COALESCE(tp.phone, ''), COALESCE(tp.qualification, ''),
		       COALESCE(tp.experience, ''), COALESCE(tp.subjects, ''), COALESCE(tp.bio, ''),
		       u.status, u.created_at
		FROM users u
		LEFT JOIN teacher_profiles tp ON tp.user_id = u.id
		WHERE u.role = 'teacher' AND u.status = $1
		ORDER BY u.created_at DESC`, status)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []TeacherApplication
	for rows.Next() {
		var t TeacherApplication
		if err := rows.Scan(&t.ID, &t.Name, &t.Email, &t.Phone, &t.Qualification, &t.Experience, &t.Subjects, &t.Bio, &t.Status, &t.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, t)
	}
	return result, nil
}

// UpdateUserStatus is used by the admin approve/reject endpoints.
func (r *Repository) UpdateUserStatus(userID int, status string) error {
	_, err := r.db.Exec(`UPDATE users SET status = $1 WHERE id = $2`, status, userID)
	return err
}
