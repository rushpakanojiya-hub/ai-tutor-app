package subjects

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the subjects Service.
type Handler struct {
	service *Service
}

// NewHandler builds a subjects Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// List handles GET /api/subjects.
func (h *Handler) List(c *gin.Context) {
	userID := c.GetInt("user_id")

	list, err := h.service.List(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load subjects")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Subjects fetched", list)
}

// ListByCategory handles GET /api/categories/:id/subjects.
func (h *Handler) ListByCategory(c *gin.Context) {
	categoryID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid category id")
		return
	}

	userID := c.GetInt("user_id")

	list, err := h.service.ListByCategory(userID, categoryID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load subjects")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Subjects fetched", list)
}

// GetByID handles GET /api/subjects/:id.
func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid subject id")
		return
	}

	userID := c.GetInt("user_id")

	subject, err := h.service.GetByID(userID, id)
	if err != nil {
		if errors.Is(err, ErrSubjectNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Subject not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load subject")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Subject fetched", subject)
}

// Create handles POST /api/subjects (admin-only).
//
// QA fix: previously had no role check - any authenticated user could
// create a subject.
func (h *Handler) Create(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	var req CreateSubjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return
	}

	id, err := h.service.Create(req)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Subject created", gin.H{"id": id})
}

// --- Admin Course Management ---

func requireAdmin(c *gin.Context) bool {
	if c.GetString("role") != "admin" {
		utils.RespondError(c, http.StatusForbidden, "Only admins can manage courses")
		return false
	}
	return true
}

// AdminList handles GET /api/admin/courses?search=&category_id=&status=.
func (h *Handler) AdminList(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	search := c.Query("search")
	var categoryID *int
	if v, err := strconv.Atoi(c.Query("category_id")); err == nil {
		categoryID = &v
	}
	var status *string
	if v := c.Query("status"); v != "" {
		status = &v
	}

	list, err := h.service.AdminList(search, categoryID, status)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load courses")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Courses fetched", list)
}

// Update handles PUT /api/subjects/:id (admin-only).
func (h *Handler) Update(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid course id")
		return
	}
	var req UpdateCourseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	if err := h.service.Update(id, req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Course updated", nil)
}

// Delete handles DELETE /api/subjects/:id (admin-only).
func (h *Handler) Delete(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid course id")
		return
	}
	if err := h.service.Delete(id); err != nil {
		if errors.Is(err, ErrCourseNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Course not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to delete course")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Course deleted", nil)
}

// Publish handles POST /api/subjects/:id/publish (admin-only).
func (h *Handler) Publish(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid course id")
		return
	}
	if err := h.service.Publish(id); err != nil {
		if errors.Is(err, ErrNoLessonsYet) {
			utils.RespondError(c, http.StatusConflict, "At least one lesson is required before publishing")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to publish course")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Course published", nil)
}

// Unpublish handles POST /api/subjects/:id/unpublish (admin-only).
func (h *Handler) Unpublish(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid course id")
		return
	}
	if err := h.service.Unpublish(id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to unpublish course")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Course unpublished", nil)
}
