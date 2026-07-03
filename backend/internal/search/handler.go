package search

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the search Service.
type Handler struct {
	service *Service
}

// NewHandler builds a search Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// Search handles GET /api/search?q=math.
func (h *Handler) Search(c *gin.Context) {
	query := c.Query("q")

	results, err := h.service.Search(query)
	if err != nil {
		if errors.Is(err, ErrEmptyQuery) {
			utils.RespondError(c, http.StatusBadRequest, "Query parameter 'q' is required")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Search failed")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Search results", results)
}