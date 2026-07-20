// AI Tutor Backend ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â Day 2 (Course & Learning Management added)
// Boots the Gin server, connects to PostgreSQL, and wires up all modules
// using Clean Architecture (handler -> service -> repository -> model).
package main

import (
	"fmt"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/database"
	"ai-tutor-backend/internal/admin"
	"ai-tutor-backend/internal/ai"
	"ai-tutor-backend/internal/aicontent"
	"ai-tutor-backend/internal/assignment"
	"ai-tutor-backend/internal/auth"
	"ai-tutor-backend/internal/badge"
	"ai-tutor-backend/internal/categories"
	"ai-tutor-backend/internal/certificate"
	"ai-tutor-backend/internal/cloudinary"
	"ai-tutor-backend/internal/enrollment"
	"ai-tutor-backend/internal/leaderboard"
	"ai-tutor-backend/internal/lessons"
	"ai-tutor-backend/internal/liveclass"
	"ai-tutor-backend/internal/livekit"
	"ai-tutor-backend/internal/middleware"
	"ai-tutor-backend/internal/notes"
	"ai-tutor-backend/internal/notification"
	"ai-tutor-backend/internal/progress"
	"ai-tutor-backend/internal/quiz"
	"ai-tutor-backend/internal/recommendations"
	"ai-tutor-backend/internal/resource"
	"ai-tutor-backend/internal/search"
	"ai-tutor-backend/internal/streak"
	"ai-tutor-backend/internal/subjects"
	"ai-tutor-backend/internal/users"
	"ai-tutor-backend/internal/xp"
	"ai-tutor-backend/internal/youtube"
	"ai-tutor-backend/pkg/logger"
)

func main() {
	cfg := configs.LoadConfig()
	gin.SetMode(cfg.GinMode)

	db := database.Connect(cfg)
	defer db.Close()

	router := gin.Default()

	// BUG FIX (security): Gin's default is to trust EVERY proxy, which the
	// startup log even warns about ("You trusted all proxies, this is NOT
	// safe"). Since c.ClientIP() (used by AuthRateLimitMiddleware for
	// login/register brute-force protection) honors the X-Forwarded-For
	// header when a proxy is trusted, "trust all" means any client can set
	// their own X-Forwarded-For to a different fake IP on every request
	// and get a fresh rate-limit bucket each time - completely bypassing
	// the brute-force protection the audit asked for.
	//
	// Elastic Beanstalk's own nginx reverse proxy sits in front of this
	// container on the loopback interface, so trusting loopback lets it
	// keep working normally while refusing to trust anything else (i.e.
	// an X-Forwarded-For coming directly from the internet is ignored).
	// If your deployment puts a different proxy/load balancer directly in
	// front of this container (not through EB's local nginx), replace
	// these with that proxy's actual IP range instead.
	if err := router.SetTrustedProxies([]string{"127.0.0.1", "::1"}); err != nil {
		logger.Error("failed to set trusted proxies", err)
	}

	router.Use(middleware.CORSMiddleware(cfg.AllowedOrigins))
	router.Use(middleware.ContentTypeFix())

	// Serves lesson PDF notes from backend/static/notes/*.pdf as
	// http://<host>:<port>/static/notes/<file>.pdf ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â real, self-hosted
	// content instead of random third-party URLs (see migration 000014).
	router.Static("/static", "./static")

	authMiddleware := middleware.AuthMiddleware(cfg.JWTSecret)

	// --- Day 1: auth + users (unchanged) ---
	authRepo := auth.NewRepository(db)
	authService := auth.NewService(authRepo, cfg)
	authHandler := auth.NewHandler(authService)

	usersRepo := users.NewRepository(db)
	usersService := users.NewService(usersRepo)
	usersHandler := users.NewHandler(usersService)

	// --- Day 2: course & learning management ---
	categoriesRepo := categories.NewRepository(db)
	categoriesService := categories.NewService(categoriesRepo)
	categoriesHandler := categories.NewHandler(categoriesService)

	subjectsRepo := subjects.NewRepository(db)
	subjectsService := subjects.NewService(subjectsRepo)
	subjectsHandler := subjects.NewHandler(subjectsService)

	// Moved up from below (Course Management needs it for lesson video/PDF/
	// assignment uploads) - cfg has no other dependency, so this is safe.
	cloudinaryClient := cloudinary.NewClient(cfg.CloudinaryCloudName, cfg.CloudinaryAPIKey, cfg.CloudinaryAPISecret)
	lessonsRepo := lessons.NewRepository(db)
	lessonsService := lessons.NewService(lessonsRepo, cloudinaryClient)

	notesRepo := notes.NewRepository(db)
	notesService := notes.NewService(notesRepo)
	notesHandler := notes.NewHandler(notesService)

	// Lesson Resource Management (additive): lessonsHandler is wired up
	// after notesService exists so it can mirror a lesson's pdf_url into
	// the notes table students already see (see lessons.Handler.syncNoteForLesson).
	lessonsHandler := lessons.NewHandler(lessonsService, notesService)

	// --- Learning Streak: real activity-based streak, fed by progress/quiz/ai below ---
	streakRepo := streak.NewRepository(db)
	streakService := streak.NewService(streakRepo)

	badgeRepo := badge.NewRepository(db)
	badgeService := badge.NewService(badgeRepo, streakRepo)
	badgeHandler := badge.NewHandler(badgeService)

	xpRepo := xp.NewRepository(db)
	xpService := xp.NewService(xpRepo, streakRepo)
	xpHandler := xp.NewHandler(xpService)

	leaderboardRepo := leaderboard.NewRepository(db)
	leaderboardService := leaderboard.NewService(leaderboardRepo, usersRepo)
	leaderboardHandler := leaderboard.NewHandler(leaderboardService)

	certRepo := certificate.NewRepository(db)
	certService := certificate.NewService(certRepo)
	certHandler := certificate.NewHandler(certService)
	streakHandler := streak.NewHandler(streakService)

	// --- Student Enrollment: auto-enrolled on lesson completion, gates
	// assignment visibility (see internal/assignment) ---
	enrollmentRepo := enrollment.NewRepository(db)
	enrollmentService := enrollment.NewService(enrollmentRepo)

	// --- Admin dashboard: real platform-wide counts ---
	adminRepo := admin.NewRepository(db, streakRepo)
	adminService := admin.NewService(adminRepo)
	adminHandler := admin.NewHandler(adminService)

	progressRepo := progress.NewRepository(db)
	progressService := progress.NewService(progressRepo, streakService, enrollmentService, badgeService, xpService, certService)
	progressHandler := progress.NewHandler(progressService)

	aiContentRepo := aicontent.NewRepository(db)
	aiContentService := aicontent.NewService(aiContentRepo)
	aiContentHandler := aicontent.NewHandler(aiContentService)

	aiRepo := ai.NewRepository(db)
	groqClient := ai.NewGroqClient(cfg.GroqAPIKey, cfg.GroqAPIURL, cfg.GroqModel)
	aiService := ai.NewService(aiRepo, subjectsRepo, groqClient, streakService)
	aiHandler := ai.NewHandler(aiService)

	// --- Assignment & AI Auto Evaluation (Phase 1: subject-level targeting) ---
	assignmentRepo := assignment.NewRepository(db)
	assignmentService := assignment.NewService(assignmentRepo, subjectsRepo, groqClient, streakService, badgeService, xpService)
	assignmentHandler := assignment.NewHandler(assignmentService)

	// --- Live Classes (Phase 1: scheduling/calendar only - no video SDK set up yet) ---
	// --- Notifications: simple polling-based (no WebSocket infra yet) ---
	notificationRepo := notification.NewRepository(db)
	notificationService := notification.NewService(notificationRepo)
	notificationHandler := notification.NewHandler(notificationService)

	liveKitTokenSvc := livekit.NewTokenService(cfg.LiveKitAPIKey, cfg.LiveKitAPISecret)
	liveKitRoomClient := livekit.NewRoomClient(cfg.LiveKitURL, cfg.LiveKitAPIKey, cfg.LiveKitAPISecret)

	resourceRepo := resource.NewRepository(db)
	resourceService := resource.NewService(resourceRepo, cloudinaryClient)
	resourceHandler := resource.NewHandler(resourceService)

	liveClassRepo := liveclass.NewRepository(db)
	liveClassService := liveclass.NewService(liveClassRepo, notificationService, liveKitTokenSvc, liveKitRoomClient, cfg.LiveKitURL, badgeService)
	liveClassHandler := liveclass.NewHandler(liveClassService)

	recommendationsRepo := recommendations.NewRepository(db)
	recommendationsService := recommendations.NewService(recommendationsRepo)
	recommendationsHandler := recommendations.NewHandler(recommendationsService)

	// search reuses the categories/subjects/lessons/aicontent repositories directly ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â
	// no separate "search" table exists, it's a fan-out query.
	searchService := search.NewService(categoriesRepo, subjectsRepo, lessonsRepo, aiContentRepo)
	searchHandler := search.NewHandler(searchService)

	// --- YouTube video integration (per-lesson recommended videos) ---
	youtubeClient := youtube.NewClient(cfg.YoutubeAPIKeys, cfg.YoutubeMaxResults)
	youtubeRepo := youtube.NewRepository(db)
	youtubeService := youtube.NewService(youtubeRepo, youtubeClient)
	youtubeHandler := youtube.NewHandler(youtubeService)

	// --- Quiz & Assessment: persisted attempts, results, analytics, AI quiz generator ---
	quizRepo := quiz.NewRepository(db)
	quizService := quiz.NewService(quizRepo, groqClient, streakService, badgeService, xpService, certService)
	quizHandler := quiz.NewHandler(quizService)

	// --- Health checks (unchanged) ---
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
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

	categories.RegisterRoutes(api, categoriesHandler, authMiddleware)
	subjects.RegisterRoutes(api, subjectsHandler, authMiddleware)
	lessons.RegisterRoutes(api, lessonsHandler, authMiddleware)
	notes.RegisterRoutes(api, notesHandler, authMiddleware)
	progress.RegisterRoutes(api, progressHandler, authMiddleware)
	aicontent.RegisterRoutes(api, aiContentHandler, authMiddleware)
	ai.RegisterRoutes(api, aiHandler, authMiddleware)
	recommendations.RegisterRoutes(api, recommendationsHandler, authMiddleware)
	search.RegisterRoutes(api, searchHandler, authMiddleware)
	youtube.RegisterRoutes(api, youtubeHandler, authMiddleware)
	quiz.RegisterRoutes(api, quizHandler, authMiddleware)
	streak.RegisterRoutes(api, streakHandler, authMiddleware)
	badgeHandler.RegisterRoutes(api, authMiddleware)
	xpHandler.RegisterRoutes(api, authMiddleware)
	leaderboardHandler.RegisterRoutes(api, authMiddleware)
	certHandler.RegisterRoutes(api, authMiddleware)
	admin.RegisterRoutes(api, adminHandler, authMiddleware, middleware.RequireAdmin())
	assignment.RegisterRoutes(api, assignmentHandler, authMiddleware, middleware.RequireTeacher())
	assignment.RegisterSubjectRoute(api, assignmentHandler, authMiddleware)
	assignment.RegisterAdminRoutes(api, assignmentHandler, authMiddleware, middleware.RequireAdmin())
	liveclass.RegisterRoutes(api, liveClassHandler, authMiddleware, middleware.RequireTeacher())
	liveclass.RegisterAdminRoutes(api, liveClassHandler, authMiddleware, middleware.RequireAdmin())
	resource.RegisterRoutes(api, resourceHandler, authMiddleware, middleware.RequireTeacher())
	notification.RegisterRoutes(api, notificationHandler, authMiddleware)

	// Role-gated routes are still intentionally absent (see Day 1 notes) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â
	// when an admin dashboard exists, the POST endpoints above (create
	// category/subject/lesson/note) should switch to
	// middleware.RequireAdmin() instead of the plain authMiddleware.

	addr := fmt.Sprintf(":%s", cfg.Port)
	logger.Info(fmt.Sprintf("Server starting on %s (env: %s)", addr, cfg.AppEnv))
	if err := router.Run(addr); err != nil {
		logger.Error("Server failed to start", err)
	}
}
