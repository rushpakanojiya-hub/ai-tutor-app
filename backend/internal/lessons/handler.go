package lessons

import (
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the lessons Service.
type Handler struct {
	service *Service
}

// NewHandler builds a lessons Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// ListBySubject handles GET /api/subjects/:id/lessons.
func (h *Handler) ListBySubject(c *gin.Context) {
	subjectID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid subject id")
		return
	}

	list, err := h.service.ListBySubject(subjectID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load lessons")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lessons fetched", list)
}

// GetByID handles GET /api/lessons/:id.
func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}

	lesson, err := h.service.GetByID(id)
	if err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load lesson")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson fetched", lesson)
}

// Create handles POST /api/lessons (admin-only).
//
// QA fix: previously had no role check - any authenticated user could
// create a lesson.
func (h *Handler) Create(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	var req CreateLessonRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "subject_id and title are required")
		return
	}

	id, err := h.service.Create(req)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "Lesson created", gin.H{"id": id})
}

// --- Admin Course Management (additive) ---

func requireAdmin(c *gin.Context) bool {
	if c.GetString("role") != "admin" {
		utils.RespondError(c, http.StatusForbidden, "Only admins can manage lessons")
		return false
	}
	return true
}

// Update handles PUT /api/lessons/:id (admin-only).
func (h *Handler) Update(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	var req UpdateLessonRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid request body")
		return
	}
	if err := h.service.Update(id, req); err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson updated", nil)
}

// Delete handles DELETE /api/lessons/:id (admin-only).
func (h *Handler) Delete(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	if err := h.service.Delete(id); err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to delete lesson")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson deleted", nil)
}

// Reorder handles POST /api/subjects/:id/lessons/reorder (admin-only) -
// drag-and-drop reordering.
func (h *Handler) Reorder(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	var req ReorderLessonsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "items array is required")
		return
	}
	if err := h.service.Reorder(req.Items); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to reorder lessons")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lessons reordered", nil)
}

const maxUploadMultipartMemory = 25 << 20 // 25MB, matches MaxUploadSizeBytes

func readUploadedFile(c *gin.Context) ([]byte, string, error) {
	file, err := c.FormFile("file")
	if err != nil {
		return nil, "", err
	}
	f, err := file.Open()
	if err != nil {
		return nil, "", err
	}
	defer f.Close()
	bytes, err := io.ReadAll(f)
	if err != nil {
		return nil, "", err
	}
	return bytes, file.Filename, nil
}

// UploadVideo handles POST /api/lessons/:id/upload-video (admin-only, multipart).
func (h *Handler) UploadVideo(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	fileBytes, filename, err := readUploadedFile(c)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A video file is required")
		return
	}
	url, err := h.service.UploadVideo(id, fileBytes, filename)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to upload video")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Video uploaded", gin.H{"video_url": url})
}

// UploadPDF handles POST /api/lessons/:id/upload-pdf (admin-only, multipart).
func (h *Handler) UploadPDF(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	fileBytes, filename, err := readUploadedFile(c)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A PDF file is required")
		return
	}
	url, err := h.service.UploadPDF(id, fileBytes, filename)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to upload PDF")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "PDF uploaded", gin.H{"pdf_url": url})
}

// UploadAssignment handles POST /api/lessons/:id/upload-assignment (admin-only, multipart).
func (h *Handler) UploadAssignment(c *gin.Context) {
	if !requireAdmin(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	fileBytes, filename, err := readUploadedFile(c)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "An assignment file is required")
		return
	}
	url, err := h.service.UploadAssignment(id, fileBytes, filename)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to upload assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment uploaded", gin.H{"assignment_url": url})
}
