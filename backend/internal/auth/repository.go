package auth

import (
	"database/sql"
	"errors"

	"github.com/lib/pq"
)

// ErrUserNotFound is returned when no user matches the given lookup.
var ErrUserNotFound = errors.New("user not found")

// ErrEmailAlreadyExists is returned when registering with a duplicate email.
var ErrEmailAlreadyExists = errors.New("email already registered")

// postgres unique_violation error code.
const pqUniqueViolation = "23505"

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
//
// QA fix ("Duplicate email registration race condition"): the previous
// version did a SELECT EXISTS check, then a separate INSERT - two
// concurrent registrations with the same email could both pass the
// check before either INSERTs. The real fix is the DB-level UNIQUE
// index on users.email (migration 026) - this method now attempts the
// INSERT directly and translates a unique-violation into
// ErrEmailAlreadyExists, which is race-proof (Postgres itself serializes
// the conflicting inserts and only lets one succeed).
func (r *Repository) CreateUser(name, email, passwordHash, role, status string) (int, error) {
	var id int
	insertQuery := `
		INSERT INTO users (name, email, password_hash, role, status)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`
	err := r.db.QueryRow(insertQuery, name, email, passwordHash, role, status).Scan(&id)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == pqUniqueViolation {
			return 0, ErrEmailAlreadyExists
		}
		return 0, err
	}
	return id, nil
}

// CreateTeacherApplication creates the user row and its teacher_profiles
// row in ONE transaction (QA fix: "Teacher registration transaction" -
// previously these were two independent calls; if the second failed,
// the user row was left behind with no profile - a permanently broken,
// half-registered account). Either both rows exist, or neither does.
func (r *Repository) CreateTeacherApplication(name, email, passwordHash, role, status, phone, qualification, experience, subjects, bio string) (int, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	var userID int
	err = tx.QueryRow(`
		INSERT INTO users (name, email, password_hash, role, status)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id`,
		name, email, passwordHash, role, status,
	).Scan(&userID)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == pqUniqueViolation {
			return 0, ErrEmailAlreadyExists
		}
		return 0, err
	}

	_, err = tx.Exec(`
		INSERT INTO teacher_profiles (user_id, phone, qualification, experience, subjects, bio)
		VALUES ($1, $2, $3, $4, $5, $6)`,
		userID, phone, qualification, experience, subjects, bio,
	)
	if err != nil {
		return 0, err
	}

	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return userID, nil
}

// CreateTeacherProfile is kept for compatibility with any other caller,
// but RegisterTeacher (service.go) now uses the transactional
// CreateTeacherApplication above instead of calling this separately.
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
//
// BUG FIX: was missing a rows.Err() check after the scan loop - a
// connection/network error that struck mid-iteration would silently
// truncate the result set instead of surfacing as an error, showing the
// admin an incomplete (but seemingly valid) approval queue.
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
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// UpdateUserStatus is used by the admin approve/reject endpoints.
func (r *Repository) UpdateUserStatus(userID int, status string) error {
	res, err := r.db.Exec(`UPDATE users SET status = $1 WHERE id = $2`, status, userID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrUserNotFound
	}
	return nil
}
