package users

import "time"

type User struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"created_at"`
}

type UpdateProfileRequest struct {
	Name  string `json:"name" binding:"required"`
	Email string `json:"email" binding:"required,email"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	NewPassword     string `json:"new_password" binding:"required"`
}

// AssignClassSectionRequest is the body for the admin-only
// PUT /api/admin/students/:id/class-section - used only for Leaderboard
// filtering, nowhere else. Students cannot set these themselves - there
// is no student-facing endpoint for this.
type AssignClassSectionRequest struct {
	Class   string `json:"class"`
	Section string `json:"section"`
}

// StudentWithClassSection is one row for the admin's student-management
// list - shows current class/section (if any) so the admin can assign
// or update them.
type StudentWithClassSection struct {
	ID      int    `json:"id"`
	Name    string `json:"name"`
	Email   string `json:"email"`
	Class   string `json:"class,omitempty"`
	Section string `json:"section,omitempty"`
}
