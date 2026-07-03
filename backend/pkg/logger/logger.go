// Package logger provides a tiny wrapper around the standard logger so the
// rest of the app doesn't import "log" directly, making it easy to swap in
// a structured logger (zap, zerolog, etc.) later without touching call sites.
package logger

import "log"

// Info logs an informational message.
func Info(msg string) {
	log.Println("[INFO] " + msg)
}

// Error logs an error message.
func Error(msg string, err error) {
	if err != nil {
		log.Printf("[ERROR] %s: %v\n", msg, err)
		return
	}
	log.Println("[ERROR] " + msg)
}