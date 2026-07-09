package certificate

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
	group := router.Group("/certificates")
	group.Use(authMiddleware)
	{
		group.GET("/mine", h.ListMine)
		group.GET("/teacher", h.ListForTeacher)
		group.GET("/all", h.ListAll)
		group.GET("/:id", h.GetByID)
	}
}

// ListMine handles GET /api/certificates/mine (student).
func (h *Handler) ListMine(c *gin.Context) {
	studentID := c.GetInt("user_id")
	certs, err := h.service.ListForStudent(studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load certificates")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Certificates fetched", certs)
}

// ListForTeacher handles GET /api/certificates/teacher.
func (h *Handler) ListForTeacher(c *gin.Context) {
	role := c.GetString("role")
	if role != "teacher" {
		utils.RespondError(c, http.StatusForbidden, "Only teachers can view this")
		return
	}
	teacherID := c.GetInt("user_id")
	certs, err := h.service.ListForTeacher(teacherID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load certificates")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Certificates fetched", certs)
}

// ListAll handles GET /api/certificates/all (admin).
func (h *Handler) ListAll(c *gin.Context) {
	role := c.GetString("role")
	if role != "admin" {
		utils.RespondError(c, http.StatusForbidden, "Only admins can view this")
		return
	}
	certs, err := h.service.ListAll()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load certificates")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Certificates fetched", certs)
}

// GetByID handles GET /api/certificates/:id - role-aware single view,
// used by the certificate viewer / PDF-download screen.
func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid certificate id")
		return
	}
	userID := c.GetInt("user_id")
	role := c.GetString("role")

	cert, err := h.service.GetForViewing(id, userID, role)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Certificate not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load certificate")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Certificate fetched", cert)
}
