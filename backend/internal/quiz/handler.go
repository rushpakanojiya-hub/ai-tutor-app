package quiz

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the quiz Service.
type Handler struct {
	service *Service
}

// NewHandler builds a quiz Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// SubmitLessonAttempt handles POST /api/quiz/lessons/:id/attempt.
func (h *Handler) SubmitLessonAttempt(c *gin.Context) {
	lessonID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}

	var req SubmitLessonAttemptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "answers array is required")
		return
	}

	userID := c.GetInt("user_id")

	result, err := h.service.SubmitLessonAttempt(userID, lessonID, req)
	if err != nil {
		switch {
		case errors.Is(err, ErrNoQuizForLesson):
			utils.RespondError(c, http.StatusNotFound, "This lesson has no quiz yet")
		case errors.Is(err, ErrAnswerCountMismatch):
			utils.RespondError(c, http.StatusBadRequest, "Number of answers does not match the quiz")
		default:
			utils.RespondError(c, http.StatusInternalServerError, "Failed to submit quiz attempt")
		}
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attempt recorded", result)
}

// SubmitFreeformAttempt handles POST /api/quiz/freeform/attempt.
func (h *Handler) SubmitFreeformAttempt(c *gin.Context) {
	var req SubmitFreeformAttemptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "topic and questions are required")
		return
	}

	userID := c.GetInt("user_id")

	result, err := h.service.SubmitFreeformAttempt(userID, req)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to submit quiz attempt")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attempt recorded", result)
}

// ListAttempts handles GET /api/quiz/attempts?lesson_id=.
func (h *Handler) ListAttempts(c *gin.Context) {
	userID := c.GetInt("user_id")
	lessonID, _ := strconv.Atoi(c.Query("lesson_id"))

	list, err := h.service.ListAttempts(userID, lessonID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load quiz history")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attempts fetched", list)
}

// GetAttempt handles GET /api/quiz/attempts/:id.
func (h *Handler) GetAttempt(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid attempt id")
		return
	}

	userID := c.GetInt("user_id")

	result, err := h.service.GetAttempt(userID, id)
	if err != nil {
		utils.RespondError(c, http.StatusNotFound, "Attempt not found")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attempt fetched", result)
}

// GetAnalytics handles GET /api/quiz/analytics.
func (h *Handler) GetAnalytics(c *gin.Context) {
	userID := c.GetInt("user_id")

	result, err := h.service.GetAnalytics(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load analytics")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Analytics fetched", result)
}

// GenerateQuiz handles POST /api/quiz/generate.
func (h *Handler) GenerateQuiz(c *gin.Context) {
	var req GenerateQuizRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "topic is required")
		return
	}

	questions, err := h.service.GenerateQuiz(c.Request.Context(), req)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to generate quiz. Please try again.")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Quiz generated", questions)
}
