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

// CreateUser inserts a new user row and returns the generated ID.
func (r *Repository) CreateUser(name, email, passwordHash, role string) (int, error) {
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
		INSERT INTO users (name, email, password_hash, role)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`
	err := r.db.QueryRow(insertQuery, name, email, passwordHash, role).Scan(&id)
	if err != nil {
		return 0, err
	}
	return id, nil
}

// FindByEmail returns the user matching the given email, or ErrUserNotFound.
func (r *Repository) FindByEmail(email string) (*User, error) {
	query := `
		SELECT id, name, email, password_hash, role, created_at
		FROM users
		WHERE email = $1
	`
	var u User
	err := r.db.QueryRow(query, email).Scan(&u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.Role, &u.CreatedAt)
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
		SELECT id, name, email, password_hash, role, created_at
		FROM users
		WHERE id = $1
	`
	var u User
	err := r.db.QueryRow(query, id).Scan(&u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.Role, &u.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}