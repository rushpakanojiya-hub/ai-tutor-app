// Package categories implements the top-level course category feature
// (Academic, Programming, Science, ...) — the first level of the
// Dashboard -> Categories -> Subjects -> Lessons hierarchy.
package categories

import "time"

// Category mirrors the "course_categories" table row.
type Category struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Icon      string    `json:"icon"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateCategoryRequest is the expected JSON body for POST /api/categories.
type CreateCategoryRequest struct {
	Name string `json:"name" binding:"required"`
	Icon string `json:"icon"`
}