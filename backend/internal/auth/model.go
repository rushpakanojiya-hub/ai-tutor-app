// Package auth implements registration, login, and profile retrieval.
package auth

import "time"

// User mirrors the "users" table row.
type User struct {
	ID           int       `json:"id"`
	Name         string    `json:"name"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	Role         string    `json:"role"`
	CreatedAt    time.Time `json:"created_at"`
}

// RegisterRequest is the expected JSON body for POST /api/auth/register.
type RegisterRequest struct {
	Name     string `json:"name" binding:"required"`
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
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