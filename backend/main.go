// AI Tutor Backend — Day 1 (finalized)
// Boots the Gin server, connects to PostgreSQL, and wires up the
// auth and users modules using Clean Architecture
// (handler -> service -> repository -> model).
package main

import (
	"fmt"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/database"
	"ai-tutor-backend/internal/auth"
	"ai-tutor-backend/internal/middleware"
	"ai-tutor-backend/internal/users"
	"ai-tutor-backend/pkg/logger"
)

func main() {
	cfg := configs.LoadConfig()
	gin.SetMode(cfg.GinMode)

	db := database.Connect(cfg)
	defer db.Close()

	router := gin.Default()
	router.Use(middleware.CORSMiddleware())

	authMiddleware := middleware.AuthMiddleware(cfg.JWTSecret)

	// --- Dependency wiring: repository -> service -> handler ---
	authRepo := auth.NewRepository(db)
	authService := auth.NewService(authRepo, cfg)
	authHandler := auth.NewHandler(authService)

	usersRepo := users.NewRepository(db)
	usersService := users.NewService(usersRepo)
	usersHandler := users.NewHandler(usersService)

	// --- Health checks ---
	// Kept at GET /health for backward compatibility with Day 1 manual testing.
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	// New, richer health check under /api, as expected by ops/uptime tooling
	// and Docker Compose's healthcheck. Actually pings the DB so "database":
	// "connected" is a real check, not a hardcoded string.
	router.GET("/api/health", func(c *gin.Context) {
		dbStatus := "connected"
		if err := db.Ping(); err != nil {
			dbStatus = "disconnected"
		}
		c.JSON(200, gin.H{
			"status":   "ok",
			"service":  "ai-tutor-backend",
			"database": dbStatus,
		})
	})

	// --- API routes ---
	api := router.Group("/api")
	authHandler.RegisterRoutes(api, authMiddleware)
	usersHandler.RegisterRoutes(api, authMiddleware)

	// Role-gated routes are intentionally not added yet (Day 1 only has the
	// student role). When Teacher/Admin routes exist, protect them like:
	//
	//   teacherGroup := api.Group("/teacher")
	//   teacherGroup.Use(authMiddleware, middleware.RequireTeacher())

	addr := fmt.Sprintf(":%s", cfg.Port)
	logger.Info(fmt.Sprintf("Server starting on %s (env: %s)", addr, cfg.AppEnv))
	if err := router.Run(addr); err != nil {
		logger.Error("Server failed to start", err)
	}
}