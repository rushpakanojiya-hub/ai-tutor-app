// Package utils contains small, dependency-light helper functions
// shared across the backend (hashing, JWT, HTTP responses, validation).
package utils

import "golang.org/x/crypto/bcrypt"

// HashPassword returns a bcrypt hash of the plain-text password.
func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

// CheckPasswordHash compares a plain-text password against a bcrypt hash.
func CheckPasswordHash(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}