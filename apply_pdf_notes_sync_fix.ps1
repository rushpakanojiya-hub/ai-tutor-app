$Root = "C:\Users\ABC\Desktop\ai_tutor_app"

# --- Create directories if they do not exist ---
New-Item -ItemType Directory -Force -Path "$Root\backend" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\backend\internal\lessons" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\backend\internal\notes" | Out-Null

# --- backend/internal/lessons/handler.go ---
$content = @'
package lessons

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/internal/notes"
	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the lessons Service.
type Handler struct {
	service *Service
	// Lesson Resource Management (additive): kept in sync with a
	// lesson's pdf_url so students see it via the existing notes list.
	notesService *notes.Service
}

// NewHandler builds a lessons Handler around a Service.
func NewHandler(service *Service, notesService *notes.Service) *Handler {
	return &Handler{service: service, notesService: notesService}
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
	if !requireAdminOrTeacher(c) {
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

// --- Lesson Resource Management (additive) ---
//
// Teachers manage lesson resources (create/edit/delete/upload/publish)
// same as admins; only admins keep exclusive rights elsewhere (course/
// category management). Student-facing GetByID/ListBySubject are
// unaffected - they stay open to any authenticated role, unchanged.
func requireAdminOrTeacher(c *gin.Context) bool {
	role := c.GetString("role")
	if role != "admin" && role != "teacher" {
		utils.RespondError(c, http.StatusForbidden, "Only admins or teachers can manage lessons")
		return false
	}
	return true
}

// Update handles PUT /api/lessons/:id (admin-only).
func (h *Handler) Update(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
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
	// Lesson Resource Management (additive): if this request touched
	// the PDF (removing it, or editing its title/description), keep
	// the mirrored note in sync too.
	if req.PDFURL != nil || req.PDFTitle != nil || req.PDFDescription != nil {
		if lesson, err := h.service.GetByID(id); err == nil {
			h.syncNoteForLesson(id, lesson.PDFURL)
		}
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson updated", nil)
}

// Delete handles DELETE /api/lessons/:id (admin-only).
func (h *Handler) Delete(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
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
	if !requireAdminOrTeacher(c) {
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

// Security audit fix (High: "File Upload Security"): the previous
// version accepted whatever c.FormFile("file") returned with no size
// check and no extension/type check at all server-side - only the
// Flutter client's FilePicker restricted extensions, which is trivial
// to bypass with a direct API call (e.g. curl). readUploadedFile now
// takes the caller's allowed extensions and enforces both the 25MB cap
// and the extension whitelist before ever reading the file into memory
// or forwarding it to Cloudinary.
func readUploadedFile(c *gin.Context, allowedExtensions []string) ([]byte, string, error) {
	file, err := c.FormFile("file")
	if err != nil {
		return nil, "", err
	}
	if file.Size > maxUploadMultipartMemory {
		return nil, "", fmt.Errorf("file exceeds the 25MB limit")
	}
	ext := strings.ToLower(filepath.Ext(file.Filename))
	allowed := false
	for _, a := range allowedExtensions {
		if ext == a {
			allowed = true
			break
		}
	}
	if !allowed {
		return nil, "", fmt.Errorf("file type %s is not allowed", ext)
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
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	fileBytes, filename, err := readUploadedFile(c, []string{".mp4", ".mov"})
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A valid video file (mp4/mov, up to 25MB) is required")
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
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	fileBytes, filename, err := readUploadedFile(c, []string{".pdf"})
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A valid PDF file (up to 25MB) is required")
		return
	}
	url, err := h.service.UploadPDF(id, fileBytes, filename)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to upload PDF")
		return
	}
	h.syncNoteForLesson(id, url)
	utils.RespondSuccess(c, http.StatusOK, "PDF uploaded", gin.H{"pdf_url": url})
}

// --- Lesson Resource Management (additive) ---

// syncNoteForLesson mirrors a lesson's pdf_url into the notes table so
// it shows up in the existing student-facing notes list. Best-effort:
// a failure here shouldn't fail the PDF upload/update/remove itself,
// so it's only logged, not returned as an error.
func (h *Handler) syncNoteForLesson(lessonID int, pdfURL string) {
	if h.notesService == nil {
		return
	}
	title := "Lesson Notes"
	if lesson, err := h.service.GetByID(lessonID); err == nil {
		if lesson.PDFTitle != "" {
			title = lesson.PDFTitle
		} else if lesson.Title != "" {
			title = lesson.Title
		}
	}
	if err := h.notesService.SyncForLesson(lessonID, title, pdfURL); err != nil {
		fmt.Printf("[lessons] failed to sync notes for lesson %d: %v\n", lessonID, err)
	}
}

// UploadAssignment handles POST /api/lessons/:id/upload-assignment (admin-only, multipart).
func (h *Handler) UploadAssignment(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	fileBytes, filename, err := readUploadedFile(c, []string{".pdf", ".doc", ".docx"})
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A valid assignment file (pdf/doc/docx, up to 25MB) is required")
		return
	}
	url, err := h.service.UploadAssignment(id, fileBytes, filename)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to upload assignment")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Assignment uploaded", gin.H{"assignment_url": url})
}

// --- Lesson Resource Management (additive) ---

// Publish handles POST /api/lessons/:id/publish (admin/teacher).
func (h *Handler) Publish(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	if err := h.service.Publish(id); err != nil {
		if errors.Is(err, ErrLessonNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Lesson not found")
			return
		}
		if errors.Is(err, ErrNoResourcesYet) {
			utils.RespondError(c, http.StatusConflict, "At least one video or PDF is required before publishing")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to publish lesson")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson published", nil)
}

// Unpublish handles POST /api/lessons/:id/unpublish (admin/teacher).
func (h *Handler) Unpublish(c *gin.Context) {
	if !requireAdminOrTeacher(c) {
		return
	}
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid lesson id")
		return
	}
	if err := h.service.Unpublish(id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to unpublish lesson")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Lesson unpublished", nil)
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\lessons\handler.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\lessons\handler.go"

# --- backend/internal/notes/repository.go ---
$content = @'
package notes

import "database/sql"

// Repository handles direct SQL access for notes.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a notes Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// FindByLessonID returns every note attached to a lesson.
func (r *Repository) FindByLessonID(lessonID int) ([]Note, error) {
	query := `SELECT id, lesson_id, title, pdf_url, created_at FROM notes WHERE lesson_id = $1 ORDER BY id`
	rows, err := r.db.Query(query, lessonID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.ID, &n.LessonID, &n.Title, &n.PDFURL, &n.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, n)
	}
	return result, nil
}

// Create inserts a new note and returns its generated ID.
func (r *Repository) Create(lessonID int, title, pdfURL string) (int, error) {
	var id int
	query := `INSERT INTO notes (lesson_id, title, pdf_url) VALUES ($1, $2, $3) RETURNING id`
	err := r.db.QueryRow(query, lessonID, title, pdfURL).Scan(&id)
	return id, err
}

// --- Lesson Resource Management (additive) ---
//
// The admin/teacher "PDF Notes" upload in Lesson Resource Management
// needs to show up in the existing student-facing notes list (the
// NotesWidget reads from this same "notes" table via ListByLesson), so
// these let the lessons package keep exactly one note in sync with a
// lesson's pdf_url without duplicating the notes UI/table.

// FindFirstByLessonID returns the first note for a lesson, or nil if none.
func (r *Repository) FindFirstByLessonID(lessonID int) (*Note, error) {
	var n Note
	query := `SELECT id, lesson_id, title, pdf_url, created_at FROM notes WHERE lesson_id = $1 ORDER BY id LIMIT 1`
	err := r.db.QueryRow(query, lessonID).Scan(&n.ID, &n.LessonID, &n.Title, &n.PDFURL, &n.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &n, nil
}

func (r *Repository) Update(id int, title, pdfURL string) error {
	_, err := r.db.Exec(`UPDATE notes SET title = $1, pdf_url = $2 WHERE id = $3`, title, pdfURL, id)
	return err
}

func (r *Repository) Delete(id int) error {
	_, err := r.db.Exec(`DELETE FROM notes WHERE id = $1`, id)
	return err
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\notes\repository.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\notes\repository.go"

# --- backend/internal/notes/service.go ---
$content = @'
package notes

import "errors"

// Service contains the business logic for notes.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a notes Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// ListByLesson returns every note attached to a lesson.
func (s *Service) ListByLesson(lessonID int) ([]Note, error) {
	return s.repo.FindByLessonID(lessonID)
}

// Create validates and inserts a new note.
func (s *Service) Create(req CreateNoteRequest) (int, error) {
	if req.Title == "" || req.PDFURL == "" {
		return 0, errors.New("title and pdf_url are required")
	}
	if req.LessonID <= 0 {
		return 0, errors.New("a valid lesson_id is required")
	}
	return s.repo.Create(req.LessonID, req.Title, req.PDFURL)
}

// --- Lesson Resource Management (additive) ---

// SyncForLesson keeps a single note in step with a lesson's pdf_url -
// used by the lessons package so uploading/replacing/removing a
// lesson's PDF (in the admin/teacher Lesson Resource Management
// dialog) also updates what students see via the existing notes list,
// without either package needing to know about the other's internals.
// An empty pdfURL removes the note; a non-empty one creates or updates it.
func (s *Service) SyncForLesson(lessonID int, title, pdfURL string) error {
	existing, err := s.repo.FindFirstByLessonID(lessonID)
	if err != nil {
		return err
	}
	if pdfURL == "" {
		if existing != nil {
			return s.repo.Delete(existing.ID)
		}
		return nil
	}
	if existing != nil {
		return s.repo.Update(existing.ID, title, pdfURL)
	}
	_, err = s.repo.Create(lessonID, title, pdfURL)
	return err
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\notes\service.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\notes\service.go"

# --- backend/main.go ---
$content = @'
// AI Tutor Backend ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Day 2 (Course & Learning Management added)
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
	"ai-tutor-backend/internal/badge"
	"ai-tutor-backend/internal/leaderboard"
	"ai-tutor-backend/internal/auth"
	"ai-tutor-backend/internal/categories"
	"ai-tutor-backend/internal/certificate"
	"ai-tutor-backend/internal/enrollment"
	"ai-tutor-backend/internal/liveclass"
	"ai-tutor-backend/internal/livekit"
	"ai-tutor-backend/internal/cloudinary"
	"ai-tutor-backend/internal/resource"
	"ai-tutor-backend/internal/lessons"
	"ai-tutor-backend/internal/middleware"
	"ai-tutor-backend/internal/notes"
	"ai-tutor-backend/internal/notification"
	"ai-tutor-backend/internal/progress"
	"ai-tutor-backend/internal/quiz"
	"ai-tutor-backend/internal/streak"
	"ai-tutor-backend/internal/recommendations"
	"ai-tutor-backend/internal/search"
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
	router.Use(middleware.CORSMiddleware(cfg.AllowedOrigins))

	// Serves lesson PDF notes from backend/static/notes/*.pdf as
	// http://<host>:<port>/static/notes/<file>.pdf ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â real, self-hosted
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
	adminRepo := admin.NewRepository(db)
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

	// search reuses the categories/subjects/lessons/aicontent repositories directly ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â
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

	// Role-gated routes are still intentionally absent (see Day 1 notes) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â
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
[System.IO.File]::WriteAllText("$Root\backend\main.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\main.go"

Write-Host ""
Write-Host "All files written successfully." -ForegroundColor Green