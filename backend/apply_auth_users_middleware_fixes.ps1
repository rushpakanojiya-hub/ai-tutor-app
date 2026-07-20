# apply_auth_users_middleware_fixes.ps1
# Run from your backend project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\backend)
# Writes: auth module (info-leak + rows.Err fixes) + users module (race condition + RequireAdmin fix)
#         + middleware content-type fix + main.go (trusted-proxy security fix).
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying auth/users/middleware fixes in $root" -ForegroundColor Cyan

# --- internal/auth/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/auth") | Out-Null
$content_internal_auth_repository_go = @'
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

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/auth/repository.go"), $content_internal_auth_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/auth/repository.go" -ForegroundColor Green

# --- internal/auth/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/auth") | Out-Null
$content_internal_auth_handler_go = @'
package auth

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/internal/middleware"
	"ai-tutor-backend/pkg/logger"
	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the auth Service.
type Handler struct {
	service *Service
}

// NewHandler builds an auth Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// RegisterRoutes attaches all /api/auth/* routes to the given router group.
//
// Security audit fix (High: "Rate Limiting"): /register, /teacher/apply,
// and /login had no rate limiting at all - brute-force password
// guessing on /login, and registration/application spam, were both
// trivially easy. Now limited per client IP (login is stricter since
// it's the classic brute-force target).
func (h *Handler) RegisterRoutes(router *gin.RouterGroup, authMiddleware gin.HandlerFunc) {
	authGroup := router.Group("/auth")
	{
		authGroup.POST("/register", middleware.AuthRateLimitMiddleware(5, time.Hour), h.Register)
		authGroup.POST("/teacher/apply", middleware.AuthRateLimitMiddleware(5, time.Hour), h.ApplyAsTeacher)
		authGroup.POST("/login", middleware.AuthRateLimitMiddleware(8, 15*time.Minute), h.Login)
		authGroup.GET("/profile", authMiddleware, h.Profile)

		// Admin-only teacher approval queue - no dedicated admin UI yet,
		// so these are called directly (e.g. via a REST client) until one
		// exists. See middleware.RequireAdmin.
		adminGroup := authGroup.Group("/admin", authMiddleware, middleware.RequireAdmin())
		{
			adminGroup.GET("/teachers/pending", h.ListPendingTeachers)
			adminGroup.POST("/teachers/:id/approve", h.ApproveTeacher)
			adminGroup.POST("/teachers/:id/reject", h.RejectTeacher)
		}
	}
}

// Register handles POST /api/auth/register (student self-registration).
//
// BUG FIX (info leak): non-validation failures (e.g. a real DB error)
// used to be sent to the client verbatim via err.Error(). Only the two
// expected, safe-to-show cases (validation, duplicate email) get a
// specific message now; anything else is logged server-side and the
// client gets a generic message.
func (h *Handler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Name, email, and password are required")
		return
	}

	if err := h.service.Register(req); err != nil {
		switch {
		case errors.Is(err, ErrEmailAlreadyExists):
			utils.RespondError(c, http.StatusConflict, "Email already registered")
		case isValidationError(err):
			utils.RespondError(c, http.StatusBadRequest, err.Error())
		default:
			logger.Error("auth: Register failed", err)
			utils.RespondError(c, http.StatusInternalServerError, "Registration failed, please try again")
		}
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "User registered", nil)
}

// ApplyAsTeacher handles POST /api/auth/teacher/apply. The account is
// created as "pending" - it cannot log in until an admin approves it.
//
// BUG FIX (info leak): same as Register above.
func (h *Handler) ApplyAsTeacher(c *gin.Context) {
	var req TeacherApplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Name, email, and password are required")
		return
	}

	if err := h.service.RegisterTeacher(req); err != nil {
		switch {
		case errors.Is(err, ErrEmailAlreadyExists):
			utils.RespondError(c, http.StatusConflict, "Email already registered")
		case isValidationError(err):
			utils.RespondError(c, http.StatusBadRequest, err.Error())
		default:
			logger.Error("auth: ApplyAsTeacher failed", err)
			utils.RespondError(c, http.StatusInternalServerError, "Application submission failed, please try again")
		}
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Application submitted successfully. Waiting for verification.", nil)
}

// isValidationError reports whether err is one of the plain input-validation
// errors Service.Register/RegisterTeacher return directly (errors.New(...)
// for invalid email format / weak password) - these are safe to show
// verbatim since they only ever describe the client's own input, never
// internal state. Anything else (DB errors, hashing errors, etc.) is not
// safe to show and is logged instead.
func isValidationError(err error) bool {
	switch err.Error() {
	case "invalid email format", "password must be at least 6 characters":
		return true
	default:
		return false
	}
}

// Login handles POST /api/auth/login (shared by students and teachers -
// the frontend never asks which role, the backend detects it).
func (h *Handler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Email and password are required")
		return
	}

	result, err := h.service.Login(req)
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidCredentials):
			utils.RespondError(c, http.StatusUnauthorized, "Invalid email or password")
		case errors.Is(err, ErrAccountPending):
			utils.RespondError(c, http.StatusForbidden, "Your teacher application is still pending approval")
		case errors.Is(err, ErrAccountRejected):
			utils.RespondError(c, http.StatusForbidden, "Your teacher application was not approved")
		case errors.Is(err, ErrAccountSuspended):
			utils.RespondError(c, http.StatusForbidden, "Your account has been suspended")
		case errors.Is(err, ErrAccountBlocked):
			utils.RespondError(c, http.StatusForbidden, "Your account has been blocked")
		default:
			logger.Error("auth: Login failed", err)
			utils.RespondError(c, http.StatusInternalServerError, "Something went wrong, please try again")
		}
		return
	}

	c.JSON(http.StatusOK, result)
}

// Profile handles GET /api/auth/profile. Requires AuthMiddleware to have run.
func (h *Handler) Profile(c *gin.Context) {
	userID := c.GetInt("user_id")

	user, err := h.service.Profile(userID)
	if err != nil {
		if errors.Is(err, ErrUserNotFound) {
			utils.RespondError(c, http.StatusNotFound, "User not found")
			return
		}
		logger.Error("auth: Profile lookup failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load profile")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Profile fetched", gin.H{
		"id":         user.ID,
		"name":       user.Name,
		"email":      user.Email,
		"role":       user.Role,
		"status":     user.Status,
		"created_at": user.CreatedAt,
	})
}

// ListPendingTeachers handles GET /api/auth/admin/teachers/pending.
func (h *Handler) ListPendingTeachers(c *gin.Context) {
	list, err := h.service.ListPendingTeachers()
	if err != nil {
		logger.Error("auth: ListPendingTeachers failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load pending teachers")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Pending teachers fetched", list)
}

// ApproveTeacher handles POST /api/auth/admin/teachers/:id/approve.
//
// QA fix ("Teacher approval validation"): the service now validates the
// target is an actual pending teacher application; this handler maps
// that new error to a clear 400 instead of a generic 500.
func (h *Handler) ApproveTeacher(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid teacher id")
		return
	}
	if err := h.service.ApproveTeacher(id); err != nil {
		if errors.Is(err, ErrNotATeacherApplication) {
			utils.RespondError(c, http.StatusBadRequest, "This user is not a pending teacher application")
			return
		}
		if errors.Is(err, ErrUserNotFound) {
			utils.RespondError(c, http.StatusNotFound, "User not found")
			return
		}
		logger.Error("auth: ApproveTeacher failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to approve teacher")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Teacher approved", nil)
}

// RejectTeacher handles POST /api/auth/admin/teachers/:id/reject.
//
// QA fix ("Teacher rejection validation"): same reasoning as ApproveTeacher.
func (h *Handler) RejectTeacher(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid teacher id")
		return
	}
	if err := h.service.RejectTeacher(id); err != nil {
		if errors.Is(err, ErrNotATeacherApplication) {
			utils.RespondError(c, http.StatusBadRequest, "This user is not a pending teacher application")
			return
		}
		if errors.Is(err, ErrUserNotFound) {
			utils.RespondError(c, http.StatusNotFound, "User not found")
			return
		}
		logger.Error("auth: RejectTeacher failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to reject teacher")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Teacher rejected", nil)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/auth/handler.go"), $content_internal_auth_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/auth/handler.go" -ForegroundColor Green

# --- internal/users/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/users") | Out-Null
$content_internal_users_repository_go = @'
package users

import (
	"database/sql"
	"errors"

	"github.com/lib/pq"
)

var ErrEmailAlreadyExists = errors.New("email already registered")
var ErrUserNotFound = errors.New("user not found")

// postgres unique_violation error code.
const pqUniqueViolation = "23505"

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// ListAll returns every user (admin/debug use).
//
// BUG FIX: was missing a rows.Err() check after the scan loop - a
// connection error mid-iteration would silently return a truncated list
// instead of an error.
func (r *Repository) ListAll() ([]User, error) {
	rows, err := r.db.Query(`SELECT id, name, email, role, created_at FROM users ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.Role, &u.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, u)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

func (r *Repository) UpdateName(id int, name string) error {
	res, err := r.db.Exec(`UPDATE users SET name = $1 WHERE id = $2`, name, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrUserNotFound
	}
	return nil
}

// UpdateNameAndEmail updates a user's name/email.
//
// BUG FIX (race condition): the previous version only did a SELECT-then-
// UPDATE existence check for the new email - the exact
// time-of-check-to-time-of-use gap already identified and fixed for
// registration (see auth.Repository.CreateUser / migration 026's
// users_email_unique_idx). Two concurrent profile updates to the same
// new email could both pass the pre-check before either UPDATEs. The
// pre-check is kept as a fast/friendly path, but the UPDATE's own
// unique-constraint violation is now the actual guarantee, translated
// into ErrEmailAlreadyExists - race-proof regardless of timing.
func (r *Repository) UpdateNameAndEmail(id int, name, email string) error {
	var existingID int
	err := r.db.QueryRow(`SELECT id FROM users WHERE email = $1`, email).Scan(&existingID)
	if err == nil && existingID != id {
		return ErrEmailAlreadyExists
	}
	if err != nil && err != sql.ErrNoRows {
		return err
	}

	res, err := r.db.Exec(`UPDATE users SET name = $1, email = $2 WHERE id = $3`, name, email, id)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == pqUniqueViolation {
			return ErrEmailAlreadyExists
		}
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrUserNotFound
	}
	return nil
}

func (r *Repository) GetPasswordHash(id int) (string, error) {
	var hash string
	err := r.db.QueryRow(`SELECT password_hash FROM users WHERE id = $1`, id).Scan(&hash)
	if err == sql.ErrNoRows {
		return "", ErrUserNotFound
	}
	return hash, err
}

func (r *Repository) UpdatePasswordHash(id int, newHash string) error {
	res, err := r.db.Exec(`UPDATE users SET password_hash = $1 WHERE id = $2`, newHash, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrUserNotFound
	}
	return nil
}

// --- Class/Section (admin-only, students-only, Leaderboard use only) ---

var ErrNotAStudent = errors.New("class and section can only be assigned to students")

// AssignClassSection sets a student's class/section - rejects if the
// target user isn't actually a student (these fields are meaningless for
// teachers/admins per the requirement).
func (r *Repository) AssignClassSection(studentID int, class, section string) error {
	var role string
	if err := r.db.QueryRow(`SELECT role FROM users WHERE id = $1`, studentID).Scan(&role); err != nil {
		if err == sql.ErrNoRows {
			return ErrUserNotFound
		}
		return err
	}
	if role != "student" {
		return ErrNotAStudent
	}
	res, err := r.db.Exec(`UPDATE users SET class = $1, section = $2 WHERE id = $3`, class, section, studentID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrUserNotFound
	}
	return nil
}

// GetClassSection is used by the Leaderboard to enforce "students only
// see their own class" - not exposed via any student-facing endpoint.
func (r *Repository) GetClassSection(studentID int) (class, section string, err error) {
	var classVal, sectionVal sql.NullString
	err = r.db.QueryRow(`SELECT class, section FROM users WHERE id = $1`, studentID).Scan(&classVal, &sectionVal)
	return classVal.String, sectionVal.String, err
}

// ListStudentsWithClassSection powers the admin's student-management
// list - so an admin can see who to assign a class/section to.
func (r *Repository) ListStudentsWithClassSection() ([]StudentWithClassSection, error) {
	rows, err := r.db.Query(`
		SELECT id, name, email, COALESCE(class, ''), COALESCE(section, '')
		FROM users WHERE role = 'student' ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []StudentWithClassSection
	for rows.Next() {
		var s StudentWithClassSection
		if err := rows.Scan(&s.ID, &s.Name, &s.Email, &s.Class, &s.Section); err != nil {
			return nil, err
		}
		result = append(result, s)
	}
	return result, rows.Err()
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/users/repository.go"), $content_internal_users_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/users/repository.go" -ForegroundColor Green

# --- internal/users/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/users") | Out-Null
$content_internal_users_handler_go = @'
package users

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/internal/middleware"
	"ai-tutor-backend/pkg/logger"
	"ai-tutor-backend/utils"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// BUG FIX (authorization): the admin routes below previously relied ONLY
// on a manual `if role != "admin"` check inside each handler function -
// functionally equivalent today, but inconsistent with every other
// admin-gated route in the app (which uses middleware.RequireAdmin()),
// and a single missed check in a future handler would silently expose
// the route. middleware.RequireAdmin() is now the actual gate; it's
// defense-in-depth for a future engineer to be unable to forget.
func (h *Handler) RegisterRoutes(router *gin.RouterGroup, authMiddleware gin.HandlerFunc) {
	usersGroup := router.Group("/users")
	usersGroup.Use(authMiddleware)
	{
		usersGroup.PUT("/profile", h.UpdateProfile)
		usersGroup.POST("/change-password", h.ChangePassword)
	}

	adminGroup := router.Group("/admin/students")
	adminGroup.Use(authMiddleware, middleware.RequireAdmin())
	{
		adminGroup.GET("", h.ListStudents)
		adminGroup.PUT("/:id/class-section", h.AssignClassSection)
	}
}

func (h *Handler) UpdateProfile(c *gin.Context) {
	userID := c.GetInt("user_id")
	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Name and a valid email are required")
		return
	}
	if err := h.service.UpdateProfile(userID, req); err != nil {
		switch {
		case errors.Is(err, ErrEmailAlreadyExists):
			utils.RespondError(c, http.StatusConflict, "This email is already in use")
		case errors.Is(err, ErrUserNotFound):
			utils.RespondError(c, http.StatusNotFound, "User not found")
		case err.Error() == "invalid email format":
			utils.RespondError(c, http.StatusBadRequest, "Invalid email format")
		default:
			logger.Error("users: UpdateProfile failed", err)
			utils.RespondError(c, http.StatusInternalServerError, "Failed to update profile")
		}
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Profile updated", nil)
}

// BUG FIX (info leak): non-validation failures used to be sent to the
// client verbatim via err.Error() - a real DB error here could leak
// internal details. Only known-safe cases get a specific message now.
func (h *Handler) ChangePassword(c *gin.Context) {
	userID := c.GetInt("user_id")
	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Current and new password are required")
		return
	}
	if err := h.service.ChangePassword(userID, req); err != nil {
		switch {
		case errors.Is(err, ErrIncorrectCurrentPassword):
			utils.RespondError(c, http.StatusUnauthorized, "Current password is incorrect")
		case errors.Is(err, ErrUserNotFound):
			utils.RespondError(c, http.StatusNotFound, "User not found")
		case err.Error() == "new password must be at least 6 characters":
			utils.RespondError(c, http.StatusBadRequest, err.Error())
		default:
			logger.Error("users: ChangePassword failed", err)
			utils.RespondError(c, http.StatusInternalServerError, "Failed to change password")
		}
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Password changed successfully", nil)
}

// ListStudents handles GET /api/admin/students - admin-only
// (enforced by middleware.RequireAdmin(), see RegisterRoutes).
func (h *Handler) ListStudents(c *gin.Context) {
	students, err := h.service.ListStudents()
	if err != nil {
		logger.Error("users: ListStudents failed", err)
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load students")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Students fetched", students)
}

// AssignClassSection handles PUT /api/admin/students/:id/class-section -
// admin-only (enforced by middleware.RequireAdmin(), see RegisterRoutes).
func (h *Handler) AssignClassSection(c *gin.Context) {
	studentID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid student id")
		return
	}

	var req AssignClassSectionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}

	if err := h.service.AssignClassSection(studentID, req); err != nil {
		switch {
		case errors.Is(err, ErrNotAStudent):
			utils.RespondError(c, http.StatusBadRequest, "Class and section can only be assigned to students")
		case errors.Is(err, ErrUserNotFound):
			utils.RespondError(c, http.StatusNotFound, "Student not found")
		default:
			logger.Error("users: AssignClassSection failed", err)
			utils.RespondError(c, http.StatusInternalServerError, "Failed to update class/section")
		}
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class/section updated", nil)
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/users/handler.go"), $content_internal_users_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/users/handler.go" -ForegroundColor Green

# --- internal/middleware/content_type_fix.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/middleware") | Out-Null
$content_internal_middleware_content_type_fix_go = @'
package middleware

import (
	"strings"

	"github.com/gin-gonic/gin"
)

// ContentTypeFix rewrites a text/plain Content-Type to application/json
// before Gin's JSON binding runs. This lets the frontend send JSON bodies
// labeled as text/plain to avoid triggering a browser CORS preflight
// (which some upstream infrastructure was blocking).
//
// BUG FIX: the previous version only matched two exact string literals
// ("text/plain" and "text/plain; charset=utf-8"). Any other equivalent
// form a client/proxy might send - different casing ("Text/Plain"), no
// space after the semicolon ("text/plain;charset=utf-8"), or a trailing
// space - fell through unrecognized, silently breaking JSON binding for
// that request. Matching is now case-insensitive and only checks the
// media type itself (ignoring any parameters).
func ContentTypeFix() gin.HandlerFunc {
	return func(c *gin.Context) {
		ct := c.GetHeader("Content-Type")
		mediaType := strings.ToLower(strings.TrimSpace(ct))
		if idx := strings.Index(mediaType, ";"); idx != -1 {
			mediaType = strings.TrimSpace(mediaType[:idx])
		}
		if mediaType == "text/plain" {
			c.Request.Header.Set("Content-Type", "application/json")
		}
		c.Next()
	}
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/middleware/content_type_fix.go"), $content_internal_middleware_content_type_fix_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/middleware/content_type_fix.go" -ForegroundColor Green

# --- main.go ---
$content_main_go = @'
// AI Tutor Backend ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Day 2 (Course & Learning Management added)
// Boots the Gin server, connects to PostgreSQL, and wires up all modules
// using Clean Architecture (handler -> service -> repository -> model).
package main

import (
	"fmt"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/database"
	"ai-tutor-backend/internal/admin"
	"ai-tutor-backend/internal/ai"
	"ai-tutor-backend/internal/aicontent"
	"ai-tutor-backend/internal/assignment"
	"ai-tutor-backend/internal/auth"
	"ai-tutor-backend/internal/badge"
	"ai-tutor-backend/internal/categories"
	"ai-tutor-backend/internal/certificate"
	"ai-tutor-backend/internal/cloudinary"
	"ai-tutor-backend/internal/enrollment"
	"ai-tutor-backend/internal/leaderboard"
	"ai-tutor-backend/internal/lessons"
	"ai-tutor-backend/internal/liveclass"
	"ai-tutor-backend/internal/livekit"
	"ai-tutor-backend/internal/middleware"
	"ai-tutor-backend/internal/notes"
	"ai-tutor-backend/internal/notification"
	"ai-tutor-backend/internal/progress"
	"ai-tutor-backend/internal/quiz"
	"ai-tutor-backend/internal/recommendations"
	"ai-tutor-backend/internal/resource"
	"ai-tutor-backend/internal/search"
	"ai-tutor-backend/internal/streak"
	"ai-tutor-backend/internal/subjects"
	"ai-tutor-backend/internal/users"
	"ai-tutor-backend/internal/xp"
	"ai-tutor-backend/internal/youtube"
	"ai-tutor-backend/pkg/logger"
)

func main() {
	cfg := configs.LoadConfig()
	gin.SetMode(cfg.GinMode)

	db := database.Connect(cfg)
	defer db.Close()

	router := gin.Default()

	// BUG FIX (security): Gin's default is to trust EVERY proxy, which the
	// startup log even warns about ("You trusted all proxies, this is NOT
	// safe"). Since c.ClientIP() (used by AuthRateLimitMiddleware for
	// login/register brute-force protection) honors the X-Forwarded-For
	// header when a proxy is trusted, "trust all" means any client can set
	// their own X-Forwarded-For to a different fake IP on every request
	// and get a fresh rate-limit bucket each time - completely bypassing
	// the brute-force protection the audit asked for.
	//
	// Elastic Beanstalk's own nginx reverse proxy sits in front of this
	// container on the loopback interface, so trusting loopback lets it
	// keep working normally while refusing to trust anything else (i.e.
	// an X-Forwarded-For coming directly from the internet is ignored).
	// If your deployment puts a different proxy/load balancer directly in
	// front of this container (not through EB's local nginx), replace
	// these with that proxy's actual IP range instead.
	if err := router.SetTrustedProxies([]string{"127.0.0.1", "::1"}); err != nil {
		logger.Error("failed to set trusted proxies", err)
	}

	router.Use(middleware.CORSMiddleware(cfg.AllowedOrigins))
	router.Use(middleware.ContentTypeFix())

	// Serves lesson PDF notes from backend/static/notes/*.pdf as
	// http://<host>:<port>/static/notes/<file>.pdf ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â real, self-hosted
	// content instead of random third-party URLs (see migration 000014).
	router.Static("/static", "./static")

	authMiddleware := middleware.AuthMiddleware(cfg.JWTSecret)

	// --- Day 1: auth + users (unchanged) ---
	authRepo := auth.NewRepository(db)
	authService := auth.NewService(authRepo, cfg)
	authHandler := auth.NewHandler(authService)

	usersRepo := users.NewRepository(db)
	usersService := users.NewService(usersRepo)
	usersHandler := users.NewHandler(usersService)

	// --- Day 2: course & learning management ---
	categoriesRepo := categories.NewRepository(db)
	categoriesService := categories.NewService(categoriesRepo)
	categoriesHandler := categories.NewHandler(categoriesService)

	subjectsRepo := subjects.NewRepository(db)
	subjectsService := subjects.NewService(subjectsRepo)
	subjectsHandler := subjects.NewHandler(subjectsService)

	// Moved up from below (Course Management needs it for lesson video/PDF/
	// assignment uploads) - cfg has no other dependency, so this is safe.
	cloudinaryClient := cloudinary.NewClient(cfg.CloudinaryCloudName, cfg.CloudinaryAPIKey, cfg.CloudinaryAPISecret)
	lessonsRepo := lessons.NewRepository(db)
	lessonsService := lessons.NewService(lessonsRepo, cloudinaryClient)

	notesRepo := notes.NewRepository(db)
	notesService := notes.NewService(notesRepo)
	notesHandler := notes.NewHandler(notesService)

	// Lesson Resource Management (additive): lessonsHandler is wired up
	// after notesService exists so it can mirror a lesson's pdf_url into
	// the notes table students already see (see lessons.Handler.syncNoteForLesson).
	lessonsHandler := lessons.NewHandler(lessonsService, notesService)

	// --- Learning Streak: real activity-based streak, fed by progress/quiz/ai below ---
	streakRepo := streak.NewRepository(db)
	streakService := streak.NewService(streakRepo)

	badgeRepo := badge.NewRepository(db)
	badgeService := badge.NewService(badgeRepo, streakRepo)
	badgeHandler := badge.NewHandler(badgeService)

	xpRepo := xp.NewRepository(db)
	xpService := xp.NewService(xpRepo, streakRepo)
	xpHandler := xp.NewHandler(xpService)

	leaderboardRepo := leaderboard.NewRepository(db)
	leaderboardService := leaderboard.NewService(leaderboardRepo, usersRepo)
	leaderboardHandler := leaderboard.NewHandler(leaderboardService)

	certRepo := certificate.NewRepository(db)
	certService := certificate.NewService(certRepo)
	certHandler := certificate.NewHandler(certService)
	streakHandler := streak.NewHandler(streakService)

	// --- Student Enrollment: auto-enrolled on lesson completion, gates
	// assignment visibility (see internal/assignment) ---
	enrollmentRepo := enrollment.NewRepository(db)
	enrollmentService := enrollment.NewService(enrollmentRepo)

	// --- Admin dashboard: real platform-wide counts ---
	adminRepo := admin.NewRepository(db, streakRepo)
	adminService := admin.NewService(adminRepo)
	adminHandler := admin.NewHandler(adminService)

	progressRepo := progress.NewRepository(db)
	progressService := progress.NewService(progressRepo, streakService, enrollmentService, badgeService, xpService, certService)
	progressHandler := progress.NewHandler(progressService)

	aiContentRepo := aicontent.NewRepository(db)
	aiContentService := aicontent.NewService(aiContentRepo)
	aiContentHandler := aicontent.NewHandler(aiContentService)

	aiRepo := ai.NewRepository(db)
	groqClient := ai.NewGroqClient(cfg.GroqAPIKey, cfg.GroqAPIURL, cfg.GroqModel)
	aiService := ai.NewService(aiRepo, subjectsRepo, groqClient, streakService)
	aiHandler := ai.NewHandler(aiService)

	// --- Assignment & AI Auto Evaluation (Phase 1: subject-level targeting) ---
	assignmentRepo := assignment.NewRepository(db)
	assignmentService := assignment.NewService(assignmentRepo, subjectsRepo, groqClient, streakService, badgeService, xpService)
	assignmentHandler := assignment.NewHandler(assignmentService)

	// --- Live Classes (Phase 1: scheduling/calendar only - no video SDK set up yet) ---
	// --- Notifications: simple polling-based (no WebSocket infra yet) ---
	notificationRepo := notification.NewRepository(db)
	notificationService := notification.NewService(notificationRepo)
	notificationHandler := notification.NewHandler(notificationService)

	liveKitTokenSvc := livekit.NewTokenService(cfg.LiveKitAPIKey, cfg.LiveKitAPISecret)
	liveKitRoomClient := livekit.NewRoomClient(cfg.LiveKitURL, cfg.LiveKitAPIKey, cfg.LiveKitAPISecret)

	resourceRepo := resource.NewRepository(db)
	resourceService := resource.NewService(resourceRepo, cloudinaryClient)
	resourceHandler := resource.NewHandler(resourceService)

	liveClassRepo := liveclass.NewRepository(db)
	liveClassService := liveclass.NewService(liveClassRepo, notificationService, liveKitTokenSvc, liveKitRoomClient, cfg.LiveKitURL, badgeService)
	liveClassHandler := liveclass.NewHandler(liveClassService)

	recommendationsRepo := recommendations.NewRepository(db)
	recommendationsService := recommendations.NewService(recommendationsRepo)
	recommendationsHandler := recommendations.NewHandler(recommendationsService)

	// search reuses the categories/subjects/lessons/aicontent repositories directly ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â
	// no separate "search" table exists, it's a fan-out query.
	searchService := search.NewService(categoriesRepo, subjectsRepo, lessonsRepo, aiContentRepo)
	searchHandler := search.NewHandler(searchService)

	// --- YouTube video integration (per-lesson recommended videos) ---
	youtubeClient := youtube.NewClient(cfg.YoutubeAPIKeys, cfg.YoutubeMaxResults)
	youtubeRepo := youtube.NewRepository(db)
	youtubeService := youtube.NewService(youtubeRepo, youtubeClient)
	youtubeHandler := youtube.NewHandler(youtubeService)

	// --- Quiz & Assessment: persisted attempts, results, analytics, AI quiz generator ---
	quizRepo := quiz.NewRepository(db)
	quizService := quiz.NewService(quizRepo, groqClient, streakService, badgeService, xpService, certService)
	quizHandler := quiz.NewHandler(quizService)

	// --- Health checks (unchanged) ---
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
	router.GET("/api/health", func(c *gin.Context) {
		dbStatus := "connected"
		if err := db.Ping(); err != nil {
			dbStatus = "disconnected"
		}
		c.JSON(200, gin.H{
			"status":   "ok",
			"service":  "ai-tutor-backend",
			"database": dbStatus,
		})
	})

	// --- API routes ---
	api := router.Group("/api")
	authHandler.RegisterRoutes(api, authMiddleware)
	usersHandler.RegisterRoutes(api, authMiddleware)

	categories.RegisterRoutes(api, categoriesHandler, authMiddleware)
	subjects.RegisterRoutes(api, subjectsHandler, authMiddleware)
	lessons.RegisterRoutes(api, lessonsHandler, authMiddleware)
	notes.RegisterRoutes(api, notesHandler, authMiddleware)
	progress.RegisterRoutes(api, progressHandler, authMiddleware)
	aicontent.RegisterRoutes(api, aiContentHandler, authMiddleware)
	ai.RegisterRoutes(api, aiHandler, authMiddleware)
	recommendations.RegisterRoutes(api, recommendationsHandler, authMiddleware)
	search.RegisterRoutes(api, searchHandler, authMiddleware)
	youtube.RegisterRoutes(api, youtubeHandler, authMiddleware)
	quiz.RegisterRoutes(api, quizHandler, authMiddleware)
	streak.RegisterRoutes(api, streakHandler, authMiddleware)
	badgeHandler.RegisterRoutes(api, authMiddleware)
	xpHandler.RegisterRoutes(api, authMiddleware)
	leaderboardHandler.RegisterRoutes(api, authMiddleware)
	certHandler.RegisterRoutes(api, authMiddleware)
	admin.RegisterRoutes(api, adminHandler, authMiddleware, middleware.RequireAdmin())
	assignment.RegisterRoutes(api, assignmentHandler, authMiddleware, middleware.RequireTeacher())
	assignment.RegisterSubjectRoute(api, assignmentHandler, authMiddleware)
	assignment.RegisterAdminRoutes(api, assignmentHandler, authMiddleware, middleware.RequireAdmin())
	liveclass.RegisterRoutes(api, liveClassHandler, authMiddleware, middleware.RequireTeacher())
	liveclass.RegisterAdminRoutes(api, liveClassHandler, authMiddleware, middleware.RequireAdmin())
	resource.RegisterRoutes(api, resourceHandler, authMiddleware, middleware.RequireTeacher())
	notification.RegisterRoutes(api, notificationHandler, authMiddleware)

	// Role-gated routes are still intentionally absent (see Day 1 notes) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â
	// when an admin dashboard exists, the POST endpoints above (create
	// category/subject/lesson/note) should switch to
	// middleware.RequireAdmin() instead of the plain authMiddleware.

	addr := fmt.Sprintf(":%s", cfg.Port)
	logger.Info(fmt.Sprintf("Server starting on %s (env: %s)", addr, cfg.AppEnv))
	if err := router.Run(addr); err != nil {
		logger.Error("Server failed to start", err)
	}
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "main.go"), $content_main_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote main.go" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Yellow
Write-Host "  1. go build ./... to sanity check"
Write-Host "  2. docker compose build --no-cache backend"
Write-Host "  3. docker compose up -d --force-recreate backend"
Write-Host "  4. Verify login rate-limiting still works correctly against the real client IP (trusted-proxy change in main.go)"