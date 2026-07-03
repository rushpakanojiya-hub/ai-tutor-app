package utils

import "github.com/gin-gonic/gin"

// SuccessResponse is the standard shape for a successful API response.
type SuccessResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message,omitempty"`
	Data    interface{} `json:"data,omitempty"`
}

// ErrorResponse is the standard shape for a failed API response.
type ErrorResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// RespondSuccess writes a consistent success JSON payload.
func RespondSuccess(c *gin.Context, statusCode int, message string, data interface{}) {
	c.JSON(statusCode, SuccessResponse{
		Success: true,
		Message: message,
		Data:    data,
	})
}

// RespondError writes a consistent error JSON payload.
func RespondError(c *gin.Context, statusCode int, message string) {
	c.JSON(statusCode, ErrorResponse{
		Success: false,
		Message: message,
	})
}