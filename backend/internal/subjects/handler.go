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

// Create handles POST /api/subjects.
// NOTE: not role-gated yet — see the same comment in categories/handler.go.
func (h *Handler) Create(c *gin.Context) {
	var req CreateSubjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "category_id and name are required")
		return
	}

	id, err := h.service.Create(req)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Subject created", gin.H{"id": id})
}
