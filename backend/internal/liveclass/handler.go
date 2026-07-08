package liveclass

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

func respondForError(c *gin.Context, err error, fallback string) {
	switch {
	case errors.Is(err, ErrNotFound):
		utils.RespondError(c, http.StatusNotFound, "Class not found")
	case errors.Is(err, ErrForbidden):
		utils.RespondError(c, http.StatusForbidden, "You can only manage classes you scheduled")
	default:
		utils.RespondError(c, http.StatusInternalServerError, fallback)
	}
}

func (h *Handler) Create(c *gin.Context) {
	var req CreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "subject_id, title, class_date, start_time, and end_time are required")
		return
	}
	teacherID := c.GetInt("user_id")
	id, err := h.service.Create(teacherID, req)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to schedule class")
		return
	}
	utils.RespondSuccess(c, http.StatusCreated, "Class scheduled", gin.H{"id": id})
}

func (h *Handler) Update(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	var req UpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.Update(id, teacherID, req); err != nil {
		respondForError(c, err, "Failed to update class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class updated", nil)
}

func (h *Handler) Cancel(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	teacherID := c.GetInt("user_id")
	if err := h.service.Cancel(id, teacherID); err != nil {
		respondForError(c, err, "Failed to cancel class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class cancelled", nil)
}

func (h *Handler) MarkCompleted(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	teacherID := c.GetInt("user_id")
	if err := h.service.MarkCompleted(id, teacherID); err != nil {
		respondForError(c, err, "Failed to update class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class marked completed", nil)
}

func (h *Handler) Delete(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.Delete(id, teacherID); err != nil {
		respondForError(c, err, "Failed to delete class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class deleted", nil)
}

func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	class, err := h.service.GetByID(id)
	if err != nil {
		respondForError(c, err, "Failed to load class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class fetched", class)
}

func (h *Handler) ListMine(c *gin.Context) {
	teacherID := c.GetInt("user_id")
	list, err := h.service.ListForTeacher(teacherID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load classes")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Classes fetched", list)
}

func (h *Handler) ListForStudent(c *gin.Context) {
	list, err := h.service.ListForStudent()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load classes")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Classes fetched", list)
}

func (h *Handler) ListAllForAdmin(c *gin.Context) {
	list, err := h.service.ListAllForAdmin()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load classes")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Classes fetched", list)
}

// AdminCancel handles POST /api/admin/live-classes/:id/cancel.
func (h *Handler) AdminCancel(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	if err := h.service.AdminCancel(id); err != nil {
		respondForError(c, err, "Failed to cancel class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class cancelled", nil)
}

// CheckIn handles POST /api/live-classes/:id/check-in (student self
// attendance).
func (h *Handler) CheckIn(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	studentID := c.GetInt("user_id")
	status, err := h.service.CheckIn(id, studentID)
	if err != nil {
		if errors.Is(err, ErrAttendanceWindowClosed) {
			utils.RespondError(c, http.StatusConflict, "Check-in is only available during the scheduled class time")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to check in")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Checked in", gin.H{"status": status})
}

// GetMyAttendance handles GET /api/live-classes/:id/my-attendance.
func (h *Handler) GetMyAttendance(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	studentID := c.GetInt("user_id")
	att, err := h.service.GetMyAttendance(id, studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load attendance")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attendance fetched", att)
}

// ListAttendance handles GET /api/live-classes/:id/attendance (teacher).
func (h *Handler) ListAttendance(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	list, err := h.service.ListAttendanceForClass(id, teacherID)
	if err != nil {
		respondForError(c, err, "Failed to load attendance")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Attendance fetched", list)
}

// AttendanceSummary handles GET /api/live-classes/attendance-summary (student).
func (h *Handler) AttendanceSummary(c *gin.Context) {
	studentID := c.GetInt("user_id")
	summary, err := h.service.GetAttendanceSummaryForStudent(studentID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load attendance summary")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Summary fetched", summary)
}

// --- Real video session (LiveKit) ---

// Start handles POST /api/live-classes/:id/start (teacher).
func (h *Handler) Start(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	result, err := h.service.Start(id, teacherID)
	if err != nil {
		respondForMeetingError(c, err, "Failed to start class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class started", result)
}

// Join handles POST /api/live-classes/:id/join (student).
func (h *Handler) Join(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	studentID := c.GetInt("user_id")
	result, err := h.service.Join(id, studentID)
	if err != nil {
		respondForMeetingError(c, err, "Failed to join class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Joined class", result)
}

// End handles POST /api/live-classes/:id/end (teacher).
func (h *Handler) End(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")
	if err := h.service.End(id, teacherID); err != nil {
		respondForMeetingError(c, err, "Failed to end class")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Class ended", nil)
}

// MeetingStatus handles GET /api/live-classes/:id/meeting-status (anyone -
// students poll this to know when to enable their Join button).
func (h *Handler) MeetingStatus(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	status, err := h.service.GetMeetingStatus(id)
	if err != nil {
		respondForError(c, err, "Failed to load meeting status")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Status fetched", gin.H{"meeting_status": status})
}

func respondForMeetingError(c *gin.Context, err error, fallback string) {
	switch {
	case errors.Is(err, ErrNotFound):
		utils.RespondError(c, http.StatusNotFound, "Class not found")
	case errors.Is(err, ErrForbidden):
		utils.RespondError(c, http.StatusForbidden, "You can only manage classes you scheduled")
	case errors.Is(err, ErrMeetingNotLive):
		utils.RespondError(c, http.StatusConflict, "The teacher hasn't started this class yet")
	case errors.Is(err, ErrMeetingAlreadyEnded):
		utils.RespondError(c, http.StatusConflict, "This class has already ended")
	default:
		utils.RespondError(c, http.StatusInternalServerError, fallback)
	}
}
