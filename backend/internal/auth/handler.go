package auth

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

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
		authGroup.POST("/login", h.Login)
		authGroup.GET("/profile", authMiddleware, h.Profile)
	}
}

// Register handles POST /api/auth/register.
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

// Login handles POST /api/auth/login.
func (h *Handler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Email and password are required")
		return
	}

	result, err := h.service.Login(req)
	if err != nil {
		if errors.Is(err, ErrInvalidCredentials) {
			utils.RespondError(c, http.StatusUnauthorized, "Invalid email or password")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Something went wrong, please try again")
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
		"created_at": user.CreatedAt,
	})
}