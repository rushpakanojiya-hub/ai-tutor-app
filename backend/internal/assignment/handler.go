package assignment

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

func respondForServiceError(c *gin.Context, err error, fallbackMsg string) {
	switch {
	case errors.Is(err, ErrNotFound):
		utils.RespondError(c, http.StatusNotFound, "Assignment not found")
	case errors.Is(err, ErrForbidden):
		utils.RespondError(c, http.StatusForbidden, "You can only manage assignments you created")
	case errors.Is(err, ErrCannotDelete):
		utils.RespondError(c, http.StatusConflict, "Published assignments must be archived before they can be deleted")
	case errors.Is(err, ErrHasSubmissions):
		utils.RespondError(c, http.StatusConflict, "Cannot unpublish - students have already submitted. Close or Archive it instead.")
	case errors.Is(err, ErrAssignmentNotOpen):
		utils.RespondError(c, http.StatusConflict, "This assignment is no longer accepting submissions")
	default:
		utils.RespondError(c, http.StatusInternalServerError, fallbackMsg)
	}
}

// --- Teacher: CRUD ---

// Create handles POST /api/assignments.
func (h *Handler) Create(c *gin.Context) {
	var req CreateAssignmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "subject_id and title are required")
		return
	}
	teacherID := c.GetInt("user_id")

	id, err := h.service.CreateAssignment(teacherID, req)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to create assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusCreated, "Assignment created", gin.H{"id": id})
}

// Update handles PUT /api/assignments/:id.
func (h *Handler) Update(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	var req UpdateAssignmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	teacherID := c.GetInt("user_id")

	if err := h.service.UpdateAssignment(id, teacherID, req); err != nil {
		respondForServiceError(c, err, "Failed to update assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment updated", nil)
}

// Delete handles DELETE /api/assignments/:id.
func (h *Handler) Delete(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	teacherID := c.GetInt("user_id")

	if err := h.service.DeleteAssignment(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to delete assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment deleted", nil)
}

// Publish handles POST /api/assignments/:id/publish.
func (h *Handler) Publish(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	teacherID := c.GetInt("user_id")
	if err := h.service.Publish(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to publish assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment published", nil)
}

// Unpublish handles POST /api/assignments/:id/unpublish.
func (h *Handler) Unpublish(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	teacherID := c.GetInt("user_id")
	if err := h.service.Unpublish(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to unpublish assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment unpublished", nil)
}

// Close handles POST /api/assignments/:id/close.
func (h *Handler) Close(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	teacherID := c.GetInt("user_id")
	if err := h.service.Close(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to close assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment closed", nil)
}

// Archive handles POST /api/assignments/:id/archive.
func (h *Handler) Archive(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	teacherID := c.GetInt("user_id")
	if err := h.service.Archive(id, teacherID); err != nil {
		respondForServiceError(c, err, "Failed to archive assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment archived", nil)
}

// GenerateAI handles POST /api/assignments/generate-ai.
func (h *Handler) GenerateAI(c *gin.Context) {
	var req GenerateAssignmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "subject_id and topic are required")
		return
	}

	draft, err := h.service.GenerateAssignment(c.Request.Context(), req)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to generate assignment. Please try again.")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment draft generated", draft)
}

// ListMine handles GET /api/assignments/mine (teacher's own assignments).
func (h *Handler) ListMine(c *gin.Context) {
	teacherID := c.GetInt("user_id")
	list, err := h.service.ListForTeacher(teacherID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load assignments")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignments fetched", list)
}

// GetByID handles GET /api/assignments/:id.
func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	a, err := h.service.GetByID(id)
	if err != nil {
		respondForServiceError(c, err, "Failed to load assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment fetched", a)
}

// ListForSubject handles GET /api/subjects/:id/assignments.
func (h *Handler) ListForSubject(c *gin.Context) {
	subjectID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid subject id")
		return
	}
	studentID := c.GetInt("user_id")
	list, err := h.service.ListPublishedForSubject(subjectID, studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load assignments")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignments fetched", list)
}

// TeacherAnalytics handles GET /api/assignments/analytics (teacher-scoped).
func (h *Handler) TeacherAnalytics(c *gin.Context) {
	teacherID := c.GetInt("user_id")
	overview, err := h.service.GetAnalytics(&teacherID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load analytics")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Analytics fetched", overview)
}

// --- Student: submissions ---

// SaveDraft handles POST /api/assignments/:id/draft.
func (h *Handler) SaveDraft(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	var req SaveDraftRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	studentID := c.GetInt("user_id")

	if err := h.service.SaveDraft(id, studentID, req.SubmissionText); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to save draft")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Draft saved", nil)
}

// Submit handles POST /api/assignments/:id/submit.
func (h *Handler) Submit(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	var req SubmitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "submission_text is required")
		return
	}
	studentID := c.GetInt("user_id")

	submission, err := h.service.Submit(c.Request.Context(), id, studentID, req.SubmissionText)
	if err != nil {
		respondForServiceError(c, err, "Failed to submit assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment submitted", submission)
}

// GetMySubmission handles GET /api/assignments/:id/my-submission.
func (h *Handler) GetMySubmission(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	studentID := c.GetInt("user_id")

	submission, err := h.service.GetMySubmission(id, studentID)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			utils.RespondSuccess(c, http.StatusOK, "No submission yet", nil)
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load submission")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Submission fetched", submission)
}

// RetryEvaluation handles POST /api/assignments/submissions/:id/retry-evaluation.
func (h *Handler) RetryEvaluation(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid submission id")
		return
	}
	studentID := c.GetInt("user_id")

	submission, err := h.service.RetryEvaluation(c.Request.Context(), id, studentID)
	if err != nil {
		respondForServiceError(c, err, "Evaluation failed again. Please try once more in a moment.")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Evaluation complete", submission)
}

// --- Teacher: review queue ---

// ListSubmissions handles GET /api/assignments/:id/submissions.
func (h *Handler) ListSubmissions(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid assignment id")
		return
	}
	teacherID := c.GetInt("user_id")

	list, err := h.service.ListSubmissionsForAssignment(id, teacherID)
	if err != nil {
		respondForServiceError(c, err, "Failed to load submissions")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Submissions fetched", list)
}

// ReviewSubmission handles POST /api/assignments/submissions/:id/review.
func (h *Handler) ReviewSubmission(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid submission id")
		return
	}
	var req TeacherReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	teacherID := c.GetInt("user_id")

	if err := h.service.TeacherReview(id, teacherID, req); err != nil {
		respondForServiceError(c, err, "Failed to save review")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Review saved", nil)
}

// --- Admin: monitoring ---

// ListAllForAdmin handles GET /api/admin/assignments.
func (h *Handler) ListAllForAdmin(c *gin.Context) {
	list, err := h.service.ListAllForAdmin()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load assignments")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignments fetched", list)
}

// AdminAnalytics handles GET /api/admin/assignments/analytics.
func (h *Handler) AdminAnalytics(c *gin.Context) {
	overview, err := h.service.GetAnalytics(nil)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load analytics")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Analytics fetched", overview)
}
