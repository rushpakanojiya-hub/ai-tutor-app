package search

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// maxQueryLen caps how long a search term can be before it's sent to the
// DB - a pure defensive bound (four unbounded ILIKE '%...%' queries run
// per search), not a real-world search term length.
const maxQueryLen = 200

// Handler adapts HTTP requests/responses to the search Service.
type Handler struct {
	service *Service
}

// NewHandler builds a search Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// Search handles GET /api/search?q=math.
//
// BUG FIX: the query was passed straight through un-trimmed and
// unbounded - a whitespace-only "q" (e.g. "   ") isn't caught by the
// ErrEmptyQuery check (since it isn't literally "") and used to run four
// pointless ILIKE queries against every table; an arbitrarily long "q"
// had no upper bound either.
func (h *Handler) Search(c *gin.Context) {
	query := strings.TrimSpace(c.Query("q"))
	if len(query) > maxQueryLen {
		query = query[:maxQueryLen]
	}

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
