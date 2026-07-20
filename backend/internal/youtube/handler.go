package youtube

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/pkg/logger"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// RegisterRoutes wires this package's endpoints into an existing Gin router
// group, matching the same package-level pattern used by categories,
// subjects, lessons, etc. Call it from main.go like:
//
//	youtube.RegisterRoutes(api, youtubeHandler, authMiddleware)
//
// authMiddleware is your existing JWT middleware â€” this package does not
// implement or modify auth. Note: this adds routes UNDER the existing
// "/lessons" URL space (/api/lessons/:id/videos) but does not touch or
// re-register the lessons package's own routes/handler.
func RegisterRoutes(router gin.IRouter, h *Handler, authMiddleware gin.HandlerFunc) {
	lessonVideos := router.Group("/lessons")
	lessonVideos.Use(authMiddleware)
	{
		lessonVideos.GET("/:id/videos", h.GetLessonVideos)
		lessonVideos.POST("/:id/videos/progress", h.SaveVideoProgress)
	}

	videos := router.Group("/videos")
	videos.Use(authMiddleware)
	{
		videos.GET("/search", h.SearchVideos)
	}
}

// GetLessonVideos handles GET /api/lessons/:id/videos
func (h *Handler) GetLessonVideos(c *gin.Context) {
	lessonID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid lesson id"})
		return
	}

	videos, err := h.service.GetVideosForLesson(c.Request.Context(), lessonID)
	if err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "lesson not found"})
			return
		}
		// SECURITY: never forward err.Error() to the client - the underlying
		// YouTube client error can (rarely) still carry request context.
		// Full detail goes to the server log only.
		logger.Error("youtube: failed to fetch lesson videos", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch videos"})
		return
	}

	c.JSON(http.StatusOK, videos)
}

// SearchVideos handles GET /api/videos/search?q=
func (h *Handler) SearchVideos(c *gin.Context) {
	q := c.Query("q")
	if q == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing q parameter"})
		return
	}

	videos, err := h.service.SearchVideos(c.Request.Context(), q)
	if err != nil {
		if errors.Is(err, ErrEmptyQuery) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "missing q parameter"})
			return
		}
		// SECURITY: this is the exact endpoint the audit flagged (critical #2)
		// as leaking the YouTube API key via "details": err.Error(). Never
		// forward the raw error to the client - log it server-side instead.
		logger.Error("youtube: search failed", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
		return
	}

	c.JSON(http.StatusOK, videos)
}

// SaveVideoProgress handles POST /api/lessons/:id/videos/progress
// Expects the authenticated user id to be set on the context by your
// existing auth middleware under the key "user_id" (set by
// middleware.AuthMiddleware from the JWT claims).
func (h *Handler) SaveVideoProgress(c *gin.Context) {
	lessonID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid lesson id"})
		return
	}

	userIDVal, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthenticated"})
		return
	}

	var userID int64
	switch v := userIDVal.(type) {
	case int64:
		userID = v
	case int:
		userID = int64(v)
	case uint:
		userID = int64(v)
	case uint64:
		userID = int64(v)
	default:
		logger.Error("youtube: unexpected user_id type in context", nil)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}

	var req VideoProgressRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payload"})
		return
	}

	if err := h.service.RecordProgress(c.Request.Context(), userID, lessonID, req); err != nil {
		logger.Error("youtube: failed to save video progress", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save progress"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
