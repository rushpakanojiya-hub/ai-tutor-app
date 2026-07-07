// Package auth implements registration, login, and profile retrieval for
// both students (self-registration, instantly active) and teachers
// (application-based, pending admin approval before they can log in).
package auth

import "time"

// Account status values. Students are always "active" immediately.
// Teachers start "pending" until an admin approves them.
const (
	StatusActive    = "active"
	StatusPending   = "pending"
	StatusRejected  = "rejected"
	StatusSuspended = "suspended"
	StatusBlocked   = "blocked"
)

// User mirrors the "users" table row.
type User struct {
	ID           int       `json:"id"`
	Name         string    `json:"name"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	Role         string    `json:"role"`
	Status       string    `json:"status"`
	CreatedAt    time.Time `json:"created_at"`
}

// RegisterRequest is the expected JSON body for POST /api/auth/register
// (student self-registration only).
type RegisterRequest struct {
	Name     string `json:"name" binding:"required"`
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// TeacherApplyRequest is the expected JSON body for POST /api/auth/teacher/apply.
// Resume/certificate file upload is intentionally not included yet - that
// needs a file storage service (e.g. Cloudinary) to be set up first.
type TeacherApplyRequest struct {
	Name         string `json:"name" binding:"required"`
	Email        string `json:"email" binding:"required"`
	Password     string `json:"password" binding:"required"`
	Phone        string `json:"phone"`
	Qualification string `json:"qualification"`
	Experience   string `json:"experience"`
	Subjects     string `json:"subjects"`
	Bio          string `json:"bio"`
}

// LoginRequest is the expected JSON body for POST /api/auth/login.
type LoginRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// AuthUserResponse is the trimmed-down user object returned after login.
type AuthUserResponse struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
	Role string `json:"role"`
}

// LoginResponse is the JSON body returned by a successful login.
type LoginResponse struct {
	Token string           `json:"token"`
	User  AuthUserResponse `json:"user"`
}

// TeacherApplication is one row for the admin approval queue.
type TeacherApplication struct {
	ID            int       `json:"id"`
	Name          string    `json:"name"`
	Email         string    `json:"email"`
	Phone         string    `json:"phone"`
	Qualification string    `json:"qualification"`
	Experience    string    `json:"experience"`
	Subjects      string    `json:"subjects"`
	Bio           string    `json:"bio"`
	Status        string    `json:"status"`
	CreatedAt     time.Time `json:"created_at"`
}
