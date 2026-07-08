package resource

import (
	"errors"
	"io"
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

// Upload handles POST /api/live-classes/:id/resources (teacher only,
// multipart/form-data with a "file" field).
func (h *Handler) Upload(c *gin.Context) {
	classID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	teacherID := c.GetInt("user_id")

	fileHeader, err := c.FormFile("file")
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "No file was attached")
		return
	}
	if fileHeader.Size > MaxUploadSizeBytes {
		utils.RespondError(c, http.StatusRequestEntityTooLarge, "File is too large (max 25MB)")
		return
	}

	file, err := fileHeader.Open()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Could not read the uploaded file")
		return
	}
	defer file.Close()

	fileBytes, err := io.ReadAll(file)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Could not read the uploaded file")
		return
	}

	res, err := h.service.Upload(classID, teacherID, fileBytes, fileHeader.Filename)
	if err != nil {
		utils.RespondError(c, http.StatusBadGateway, "Failed to upload file. Please try again.")
		return
	}

	utils.RespondSuccess(c, http.StatusCreated, "File uploaded", res)
}

// List handles GET /api/live-classes/:id/resources (any authenticated
// participant of the class).
func (h *Handler) List(c *gin.Context) {
	classID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid class id")
		return
	}
	resources, err := h.service.ListForClass(classID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load resources")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Resources fetched", resources)
}

// Delete handles DELETE /api/live-classes/:id/resources/:resourceId
// (teacher only, and only the uploader).
func (h *Handler) Delete(c *gin.Context) {
	resourceID, err := strconv.Atoi(c.Param("resourceId"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid resource id")
		return
	}
	teacherID := c.GetInt("user_id")

	if err := h.service.Delete(resourceID, teacherID); err != nil {
		switch {
		case errors.Is(err, ErrNotFound):
			utils.RespondError(c, http.StatusNotFound, "Resource not found")
		case errors.Is(err, ErrForbidden):
			utils.RespondError(c, http.StatusForbidden, "You can only delete files you uploaded")
		default:
			utils.RespondError(c, http.StatusInternalServerError, "Failed to delete resource")
		}
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Resource deleted", nil)
}
