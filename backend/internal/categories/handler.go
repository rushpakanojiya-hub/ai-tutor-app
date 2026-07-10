package categories

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the categories Service.
type Handler struct {
	service *Service
}

// NewHandler builds a categories Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// List handles GET /api/categories.
func (h *Handler) List(c *gin.Context) {
	list, err := h.service.List()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load categories")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Categories fetched", list)
}

// GetByID handles GET /api/categories/:id.
func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid category id")
		return
	}

	category, err := h.service.GetByID(id)
	if err != nil {
		if errors.Is(err, ErrCategoryNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Category not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load category")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Category fetched", category)
}

// Create handles POST /api/categories (admin-only).
//
// QA fix: this endpoint previously had no role check at all - any
// authenticated user (including students) could create a course
// category. Categories/Subjects/Lessons/Notes Create now all require
// admin, matching how their Update/Delete counterparts are already gated.
func (h *Handler) Create(c *gin.Context) {
	if c.GetString("role") != "admin" {
		utils.RespondError(c, http.StatusForbidden, "Only admins can create categories")
		return
	}
	var req CreateCategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return
	}

	id, err := h.service.Create(req)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Category created", gin.H{"id": id})
}

// Update handles PUT /api/categories/:id (admin-only) - part of Course
// Categories management.
func (h *Handler) Update(c *gin.Context) {
	if c.GetString("role") != "admin" {
		utils.RespondError(c, http.StatusForbidden, "Only admins can manage categories")
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid category id")
		return
	}
	var req UpdateCategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	if err := h.service.Update(id, req); err != nil {
		if errors.Is(err, ErrCategoryNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Category not found")
			return
		}
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Category updated", nil)
}
