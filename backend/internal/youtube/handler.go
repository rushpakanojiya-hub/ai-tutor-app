package youtube

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
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
// authMiddleware is your existing JWT middleware — this package does not
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch videos", "details": err.Error()})
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, videos)
}

// SaveVideoProgress handles POST /api/lessons/:id/videos/progress
// Expects the authenticated user id to be set on the context by your
// existing auth middleware under the key "userID" (adjust if your
// middleware uses a different key).
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid user id type in context"})
		return
	}

	var req VideoProgressRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payload", "details": err.Error()})
		return
	}

	if err := h.service.RecordProgress(c.Request.Context(), userID, lessonID, req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save progress", "details": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
