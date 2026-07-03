package utils

import "regexp"

var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

// IsValidEmail does a lightweight format check on an email string.
func IsValidEmail(email string) bool {
	return emailRegex.MatchString(email)
}

// IsValidPassword enforces a minimal password policy for Day 1 (min 6 chars).
func IsValidPassword(password string) bool {
	return len(password) >= 6
}