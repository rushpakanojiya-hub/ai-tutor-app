$files = @{}
$files['main.go'] = @'
// AI Tutor Backend — Day 2 (Course & Learning Management added)
// Boots the Gin server, connects to PostgreSQL, and wires up all modules
// using Clean Architecture (handler -> service -> repository -> model).
package main

import (
	"fmt"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/database"
	"ai-tutor-backend/internal/auth"
	"ai-tutor-backend/internal/categories"
	"ai-tutor-backend/internal/lessons"
	"ai-tutor-backend/internal/middleware"
	"ai-tutor-backend/internal/notes"
	"ai-tutor-backend/internal/progress"
	"ai-tutor-backend/internal/search"
	"ai-tutor-backend/internal/subjects"
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

	lessonsRepo := lessons.NewRepository(db)
	lessonsService := lessons.NewService(lessonsRepo)
	lessonsHandler := lessons.NewHandler(lessonsService)

	notesRepo := notes.NewRepository(db)
	notesService := notes.NewService(notesRepo)
	notesHandler := notes.NewHandler(notesService)

	progressRepo := progress.NewRepository(db)
	progressService := progress.NewService(progressRepo)
	progressHandler := progress.NewHandler(progressService)

	// search reuses the categories/subjects/lessons repositories directly —
	// no separate "search" table exists, it's a fan-out query.
	searchService := search.NewService(categoriesRepo, subjectsRepo, lessonsRepo)
	searchHandler := search.NewHandler(searchService)

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
	search.RegisterRoutes(api, searchHandler, authMiddleware)

	// Role-gated routes are still intentionally absent (see Day 1 notes) —
	// when an admin dashboard exists, the POST endpoints above (create
	// category/subject/lesson/note) should switch to
	// middleware.RequireAdmin() instead of the plain authMiddleware.

	addr := fmt.Sprintf(":%s", cfg.Port)
	logger.Info(fmt.Sprintf("Server starting on %s (env: %s)", addr, cfg.AppEnv))
	if err := router.Run(addr); err != nil {
		logger.Error("Server failed to start", err)
	}
}

'@
$files['migrations\000010_create_progress_table.up.sql'] = @'
-- Tracks which lessons each user has completed. One row per (user, lesson);
-- re-marking a lesson complete just updates completed_at instead of erroring.
CREATE TABLE IF NOT EXISTS lesson_progress (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lesson_id INTEGER NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
    completed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, lesson_id)
);

CREATE INDEX IF NOT EXISTS idx_lesson_progress_user ON lesson_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_lesson_progress_lesson ON lesson_progress(lesson_id);

'@
$files['migrations\000010_create_progress_table.down.sql'] = @'
DROP TABLE IF EXISTS lesson_progress;

'@
$files['migrations\000011_add_sample_media_urls.up.sql'] = @'
-- Adds real, publicly hosted sample video/PDF URLs to the seeded lessons
-- (migration 000009 left video_url/pdf_url NULL) so video playback and PDF
-- notes can actually be tested end-to-end, not just their empty states.
UPDATE lessons SET
    video_url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'
WHERE title = 'Introduction' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

UPDATE lessons SET
    video_url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4'
WHERE title = 'Algebra' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

UPDATE lessons SET
    video_url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4'
WHERE title = 'Geometry' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

-- Sample PDF notes (W3C's public dummy.pdf) attached to each Mathematics lesson.
INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, l.title || ' - Notes', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'
FROM lessons l
JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Mathematics';

'@
$files['migrations\000011_add_sample_media_urls.down.sql'] = @'
DELETE FROM notes WHERE title LIKE '% - Notes' AND lesson_id IN (
    SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics'
);

UPDATE lessons SET video_url = NULL
WHERE subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

'@
$files['internal\progress\model.go'] = @'
// Package progress tracks which lessons each user has completed
// (lesson_progress table) and derives per-subject completion percentages.
package progress

import "time"

// LessonProgress mirrors a "lesson_progress" table row.
type LessonProgress struct {
	ID          int       `json:"id"`
	UserID      int       `json:"user_id"`
	LessonID    int       `json:"lesson_id"`
	CompletedAt time.Time `json:"completed_at"`
}

// SubjectProgress is the aggregated view returned to the Flutter app:
// how many of a subject's lessons the current user has completed, and
// which specific lesson IDs — so the Lessons screen can render checkmarks
// without a separate call per lesson.
type SubjectProgress struct {
	SubjectID           int     `json:"subject_id"`
	TotalLessons        int     `json:"total_lessons"`
	CompletedLessons    int     `json:"completed_lessons"`
	Percentage          float64 `json:"percentage"` // 0.0 - 1.0
	CompletedLessonIDs  []int   `json:"completed_lesson_ids"`
}

'@
$files['internal\progress\repository.go'] = @'
package progress

import "database/sql"

// Repository handles direct SQL access for lesson_progress.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a progress Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// MarkComplete records that userID has completed lessonID. Calling this
// again for the same (user, lesson) pair just refreshes completed_at
// instead of erroring — re-watching a lesson keeps it marked complete.
func (r *Repository) MarkComplete(userID, lessonID int) error {
	query := `
		INSERT INTO lesson_progress (user_id, lesson_id, completed_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (user_id, lesson_id)
		DO UPDATE SET completed_at = NOW()
	`
	_, err := r.db.Exec(query, userID, lessonID)
	return err
}

// GetSubjectProgress returns the total lesson count for a subject, the
// count and IDs of lessons userID has completed within it.
func (r *Repository) GetSubjectProgress(userID, subjectID int) (*SubjectProgress, error) {
	sp := &SubjectProgress{SubjectID: subjectID}

	// Total lessons in the subject.
	err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons WHERE subject_id = $1`, subjectID).Scan(&sp.TotalLessons)
	if err != nil {
		return nil, err
	}

	// Completed lesson IDs for this user within the subject.
	rows, err := r.db.Query(`
		SELECT l.id
		FROM lessons l
		JOIN lesson_progress lp ON lp.lesson_id = l.id AND lp.user_id = $1
		WHERE l.subject_id = $2
	`, userID, subjectID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		sp.CompletedLessonIDs = append(sp.CompletedLessonIDs, id)
	}
	sp.CompletedLessons = len(sp.CompletedLessonIDs)

	if sp.TotalLessons > 0 {
		sp.Percentage = float64(sp.CompletedLessons) / float64(sp.TotalLessons)
	}

	return sp, nil
}

'@
$files['internal\progress\service.go'] = @'
package progress

// Service contains the business logic for progress tracking.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a progress Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// MarkLessonComplete records lessonID as completed by userID.
func (s *Service) MarkLessonComplete(userID, lessonID int) error {
	return s.repo.MarkComplete(userID, lessonID)
}

// SubjectProgress returns userID's completion summary for a subject.
func (s *Service) SubjectProgress(userID, subjectID int) (*SubjectProgress, error) {
	return s.repo.GetSubjectProgress(userID, subjectID)
}

'@
$files['internal\progress\handler.go'] = @'
package progress

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the progress Service.
type Handler struct {
	service *Service
}

// NewHandler builds a progress Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// MarkComplete handles POST /api/progress/lessons/:id/complete.
// The user is identified from the JWT (set by AuthMiddleware), not from
// the request body — a user can only mark their own progress.
func (h *Handler) MarkComplete(c *gin.Context) {
	lessonID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}

	userID := c.GetInt("user_id")

	if err := h.service.MarkLessonComplete(userID, lessonID); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to save progress")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Lesson marked complete", nil)
}

// GetSubjectProgress handles GET /api/progress/subjects/:id.
func (h *Handler) GetSubjectProgress(c *gin.Context) {
	subjectID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid subject id")
		return
	}

	userID := c.GetInt("user_id")

	result, err := h.service.SubjectProgress(userID, subjectID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load progress")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Progress fetched", result)
}

'@
$files['internal\progress\routes.go'] = @'
package progress

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches /api/progress/* routes. All require auth since
// progress is always scoped to the current user.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	group := router.Group("/progress")
	group.Use(authMiddleware)
	{
		group.POST("/lessons/:id/complete", handler.MarkComplete)
		group.GET("/subjects/:id", handler.GetSubjectProgress)
	}
}

'@

foreach ($path in $files.Keys) {
    $fullPath = Join-Path $PWD $path
    $dir = Split-Path $fullPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($fullPath, $files[$path], [System.Text.UTF8Encoding]::new($false))
    Write-Host "Created/Updated: $path"
}
Write-Host ""
Write-Host "Backend progress-tracking files applied successfully."
