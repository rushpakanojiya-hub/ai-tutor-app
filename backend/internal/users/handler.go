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
