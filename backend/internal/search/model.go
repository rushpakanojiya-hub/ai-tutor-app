// Package search implements the global "search across everything" feature
// (Feature 6), reusing the existing categories/subjects/lessons repositories
// instead of duplicating query logic.
package search

import (
	"ai-tutor-backend/internal/categories"
	"ai-tutor-backend/internal/lessons"
	"ai-tutor-backend/internal/subjects"
)

// Results bundles matches from all three searchable entities into one
// response, so the Flutter search screen can render sectioned results
// from a single API call.
type Results struct {
	Categories []categories.Category `json:"categories"`
	Subjects   []subjects.Subject    `json:"subjects"`
	Lessons    []lessons.Lesson      `json:"lessons"`
}