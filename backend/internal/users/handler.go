package users

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) RegisterRoutes(router *gin.RouterGroup, authMiddleware gin.HandlerFunc) {
	usersGroup := router.Group("/users")
	usersGroup.Use(authMiddleware)
	{
		usersGroup.PUT("/profile", h.UpdateProfile)
		usersGroup.POST("/change-password", h.ChangePassword)
	}

	adminGroup := router.Group("/admin/students")
	adminGroup.Use(authMiddleware)
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
		if errors.Is(err, ErrEmailAlreadyExists) {
			utils.RespondError(c, http.StatusConflict, "This email is already in use")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update profile")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Profile updated", nil)
}

func (h *Handler) ChangePassword(c *gin.Context) {
	userID := c.GetInt("user_id")
	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Current and new password are required")
		return
	}
	if err := h.service.ChangePassword(userID, req); err != nil {
		if errors.Is(err, ErrIncorrectCurrentPassword) {
			utils.RespondError(c, http.StatusUnauthorized, "Current password is incorrect")
			return
		}
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Password changed successfully", nil)
}

// ListStudents handles GET /api/admin/students - admin-only.
func (h *Handler) ListStudents(c *gin.Context) {
	role := c.GetString("role")
	if role != "admin" {
		utils.RespondError(c, http.StatusForbidden, "Only admins can view the student list")
		return
	}
	students, err := h.service.ListStudents()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load students")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Students fetched", students)
}

// AssignClassSection handles PUT /api/admin/students/:id/class-section -
// admin-only.
func (h *Handler) AssignClassSection(c *gin.Context) {
	role := c.GetString("role")
	if role != "admin" {
		utils.RespondError(c, http.StatusForbidden, "Only admins can assign class/section")
		return
	}

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
		if errors.Is(err, ErrNotAStudent) {
			utils.RespondError(c, http.StatusBadRequest, "Class and section can only be assigned to students")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to update class/section")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class/section updated", nil)
}
