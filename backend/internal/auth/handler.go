package auth

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/internal/middleware"
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
func (h *Handler) RegisterRoutes(router *gin.RouterGroup, authMiddleware gin.HandlerFunc) {
	authGroup := router.Group("/auth")
	{
		authGroup.POST("/register", h.Register)
		authGroup.POST("/teacher/apply", h.ApplyAsTeacher)
		authGroup.POST("/login", h.Login)
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
func (h *Handler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Name, email, and password are required")
		return
	}

	if err := h.service.Register(req); err != nil {
		if errors.Is(err, ErrEmailAlreadyExists) {
			utils.RespondError(c, http.StatusConflict, "Email already registered")
			return
		}
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "User registered", nil)
}

// ApplyAsTeacher handles POST /api/auth/teacher/apply. The account is
// created as "pending" - it cannot log in until an admin approves it.
func (h *Handler) ApplyAsTeacher(c *gin.Context) {
	var req TeacherApplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Name, email, and password are required")
		return
	}

	if err := h.service.RegisterTeacher(req); err != nil {
		if errors.Is(err, ErrEmailAlreadyExists) {
			utils.RespondError(c, http.StatusConflict, "Email already registered")
			return
		}
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Application submitted successfully. Waiting for verification.", nil)
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
		utils.RespondError(c, http.StatusNotFound, "User not found")
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
		utils.RespondError(c, http.StatusInternalServerError, "Failed to reject teacher")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Teacher rejected", nil)
}
