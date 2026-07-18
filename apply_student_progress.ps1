$Root = "C:\Users\ABC\Desktop\ai_tutor_app"

New-Item -ItemType Directory -Force -Path "$Root\backend" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\backend\internal\admin" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\models" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\screens\admin" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\screens\profile" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\services" | Out-Null

# --- backend/internal/admin/model.go ---
$content = @'
// Package admin implements the admin-only dashboard: real platform-wide
// counts (students, teachers, subjects, lessons, quiz attempts, AI chats)
// computed directly from existing tables. Teacher application review
// reuses the endpoints already built in internal/auth
// (/api/auth/admin/teachers/*) - this package doesn't duplicate that.
package admin

// DashboardStats is the response for GET /api/admin/dashboard. Every
// field is a real COUNT query - nothing here is estimated or fabricated.
type DashboardStats struct {
	TotalStudents      int `json:"total_students"`
	TotalTeachers      int `json:"total_teachers"`       // active teachers only
	PendingTeachers    int `json:"pending_teachers"`
	TotalSubjects      int `json:"total_subjects"`        // closest equivalent to "courses" in this app's data model
	TotalLessons       int `json:"total_lessons"`
	TotalQuizAttempts  int `json:"total_quiz_attempts"`
	TotalAiChatSessions int `json:"total_ai_chat_sessions"`
	NewRegistrationsThisWeek int `json:"new_registrations_this_week"`
}

// --- Student Progress Overview (additive) ---
//
// One row per student for the admin-only "Student Progress" screen -
// lessons completed (count + percentage of everything on the
// platform), average quiz score, and current learning streak. All
// computed directly from existing tables (lesson_progress,
// quiz_attempts, user_activity_days), same "no fabricated numbers"
// approach as DashboardStats above.
type StudentProgress struct {
	UserID            int      `json:"user_id"`
	Name              string   `json:"name"`
	Email             string   `json:"email"`
	Class             string   `json:"class"`
	Section           string   `json:"section"`
	LessonsCompleted  int      `json:"lessons_completed"`
	TotalLessons      int      `json:"total_lessons"`
	CompletionPercent float64  `json:"completion_percent"` // 0.0 - 1.0
	AverageQuizScore  *float64 `json:"average_quiz_score"` // null if the student has no quiz attempts yet
	CurrentStreak     int      `json:"current_streak"`
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\admin\model.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\admin\model.go"

# --- backend/internal/admin/repository.go ---
$content = @'
package admin

import (
	"database/sql"

	"ai-tutor-backend/internal/streak"
)

// Repository runs simple, direct COUNT queries against existing tables -
// no new tables needed for this dashboard.
type Repository struct {
	db *sql.DB
	// Student Progress Overview (additive) - reuses streak's existing
	// "consecutive active days" logic instead of duplicating the
	// date-diff calculation here.
	streakRepo *streak.Repository
}

func NewRepository(db *sql.DB, streakRepo *streak.Repository) *Repository {
	return &Repository{db: db, streakRepo: streakRepo}
}

func (r *Repository) GetDashboardStats() (*DashboardStats, error) {
	stats := &DashboardStats{}

	if err := r.db.QueryRow(`SELECT COUNT(*) FROM users WHERE role = 'student'`).Scan(&stats.TotalStudents); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM users WHERE role = 'teacher' AND status = 'active'`).Scan(&stats.TotalTeachers); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM users WHERE role = 'teacher' AND status = 'pending'`).Scan(&stats.PendingTeachers); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM subjects`).Scan(&stats.TotalSubjects); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons`).Scan(&stats.TotalLessons); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM quiz_attempts`).Scan(&stats.TotalQuizAttempts); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM ai_chat_sessions`).Scan(&stats.TotalAiChatSessions); err != nil {
		return nil, err
	}
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '7 days'`).Scan(&stats.NewRegistrationsThisWeek); err != nil {
		return nil, err
	}

	return stats, nil
}

// --- Student Progress Overview (additive) ---

// ListStudentProgress returns one row per student with lessons
// completed, average quiz score, and current streak.
func (r *Repository) ListStudentProgress() ([]StudentProgress, error) {
	var totalLessons int
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons`).Scan(&totalLessons); err != nil {
		return nil, err
	}

	rows, err := r.db.Query(`
		SELECT
			u.id, u.name, u.email,
			COALESCE(u.class, ''), COALESCE(u.section, ''),
			(SELECT COUNT(DISTINCT lp.lesson_id) FROM lesson_progress lp WHERE lp.user_id = u.id),
			(SELECT AVG(qa.score_percent) FROM quiz_attempts qa WHERE qa.user_id = u.id)
		FROM users u
		WHERE u.role = 'student'
		ORDER BY u.name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []StudentProgress
	for rows.Next() {
		var sp StudentProgress
		var avgScore sql.NullFloat64
		if err := rows.Scan(&sp.UserID, &sp.Name, &sp.Email, &sp.Class, &sp.Section, &sp.LessonsCompleted, &avgScore); err != nil {
			return nil, err
		}
		sp.TotalLessons = totalLessons
		if totalLessons > 0 {
			sp.CompletionPercent = float64(sp.LessonsCompleted) / float64(totalLessons)
		}
		if avgScore.Valid {
			v := avgScore.Float64
			sp.AverageQuizScore = &v
		}
		streakCount, err := r.streakRepo.GetCurrentStreak(sp.UserID)
		if err != nil {
			return nil, err
		}
		sp.CurrentStreak = streakCount
		result = append(result, sp)
	}
	return result, rows.Err()
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\admin\repository.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\admin\repository.go"

# --- backend/internal/admin/service.go ---
$content = @'
package admin

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) GetDashboardStats() (*DashboardStats, error) {
	return s.repo.GetDashboardStats()
}

// --- Student Progress Overview (additive) ---

func (s *Service) ListStudentProgress() ([]StudentProgress, error) {
	return s.repo.ListStudentProgress()
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\admin\service.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\admin\service.go"

# --- backend/internal/admin/handler.go ---
$content = @'
package admin

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// GetDashboard handles GET /api/admin/dashboard.
func (h *Handler) GetDashboard(c *gin.Context) {
	stats, err := h.service.GetDashboardStats()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load dashboard stats")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Dashboard stats fetched", stats)
}

// --- Student Progress Overview (additive) ---

// GetStudentProgress handles GET /api/admin/students/progress.
func (h *Handler) GetStudentProgress(c *gin.Context) {
	list, err := h.service.ListStudentProgress()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load student progress")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Student progress fetched", list)
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\admin\handler.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\admin\handler.go"

# --- backend/internal/admin/routes.go ---
$content = @'
package admin

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches GET /api/admin/dashboard - guarded by
// authMiddleware + requireAdmin (passed in from main.go, same
// middleware.RequireAdmin() used by the teacher-approval endpoints).
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware, requireAdmin gin.HandlerFunc) {
	group := router.Group("/admin")
	group.Use(authMiddleware, requireAdmin)
	{
		group.GET("/dashboard", handler.GetDashboard)
		// Student Progress Overview (additive)
		group.GET("/students/progress", handler.GetStudentProgress)
	}
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\admin\routes.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\admin\routes.go"

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

# --- frontend/lib/models/admin_models.dart ---
$content = @'
/// Real, admin-only platform-wide counts. Every field comes from a COUNT
/// query on existing tables - nothing here is estimated.
class AdminDashboardStats {
  final int totalStudents;
  final int totalTeachers;
  final int pendingTeachers;
  final int totalSubjects;
  final int totalLessons;
  final int totalQuizAttempts;
  final int totalAiChatSessions;
  final int newRegistrationsThisWeek;

  AdminDashboardStats({
    required this.totalStudents,
    required this.totalTeachers,
    required this.pendingTeachers,
    required this.totalSubjects,
    required this.totalLessons,
    required this.totalQuizAttempts,
    required this.totalAiChatSessions,
    required this.newRegistrationsThisWeek,
  });

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    return AdminDashboardStats(
      totalStudents: json['total_students'] as int? ?? 0,
      totalTeachers: json['total_teachers'] as int? ?? 0,
      pendingTeachers: json['pending_teachers'] as int? ?? 0,
      totalSubjects: json['total_subjects'] as int? ?? 0,
      totalLessons: json['total_lessons'] as int? ?? 0,
      totalQuizAttempts: json['total_quiz_attempts'] as int? ?? 0,
      totalAiChatSessions: json['total_ai_chat_sessions'] as int? ?? 0,
      newRegistrationsThisWeek: json['new_registrations_this_week'] as int? ?? 0,
    );
  }
}

// --- Student Progress Overview (additive) ---
//
// One row per student for the admin-only "Student Progress" screen -
// lessons completed, average quiz score, and current streak.
class StudentProgressModel {
  final int userId;
  final String name;
  final String email;
  final String classValue;
  final String section;
  final int lessonsCompleted;
  final int totalLessons;
  final double completionPercent; // 0.0 - 1.0
  final double? averageQuizScore; // null if no quiz attempts yet
  final int currentStreak;

  StudentProgressModel({
    required this.userId,
    required this.name,
    required this.email,
    required this.classValue,
    required this.section,
    required this.lessonsCompleted,
    required this.totalLessons,
    required this.completionPercent,
    required this.averageQuizScore,
    required this.currentStreak,
  });

  factory StudentProgressModel.fromJson(Map<String, dynamic> json) {
    return StudentProgressModel(
      userId: json['user_id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      classValue: json['class'] as String? ?? '',
      section: json['section'] as String? ?? '',
      lessonsCompleted: json['lessons_completed'] as int? ?? 0,
      totalLessons: json['total_lessons'] as int? ?? 0,
      completionPercent: (json['completion_percent'] as num?)?.toDouble() ?? 0.0,
      averageQuizScore: (json['average_quiz_score'] as num?)?.toDouble(),
      currentStreak: json['current_streak'] as int? ?? 0,
    );
  }
}

/// One teacher application in the admin review queue.
class TeacherApplicationModel {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String qualification;
  final String experience;
  final String subjects;
  final String bio;
  final String status;
  final DateTime createdAt;

  TeacherApplicationModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.qualification,
    required this.experience,
    required this.subjects,
    required this.bio,
    required this.status,
    required this.createdAt,
  });

  factory TeacherApplicationModel.fromJson(Map<String, dynamic> json) {
    return TeacherApplicationModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      qualification: json['qualification'] as String? ?? '',
      experience: json['experience'] as String? ?? '',
      subjects: json['subjects'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\models\admin_models.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\models\admin_models.dart"

# --- frontend/lib/services/admin_service.dart ---
$content = @'
import '../core/constants/api_constants.dart';
import '../models/admin_models.dart';
import 'api_service.dart';

/// Talks to the admin-only /api/admin/* and /api/auth/admin/* endpoints.
/// Every call requires the signed-in user to have role == 'admin' -
/// the backend enforces this (middleware.RequireAdmin), this service just
/// makes the calls.
class AdminService {
  final ApiService _api = ApiService();

  Future<AdminDashboardStats> fetchDashboardStats() async {
    final response = await _api.get(ApiConstants.adminDashboard);
    return AdminDashboardStats.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<TeacherApplicationModel>> fetchPendingTeachers() async {
    final response = await _api.get(ApiConstants.adminPendingTeachers);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => TeacherApplicationModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<void> approveTeacher(int id) async {
    await _api.post(ApiConstants.adminApproveTeacher(id), {});
  }

  Future<void> rejectTeacher(int id) async {
    await _api.post(ApiConstants.adminRejectTeacher(id), {});
  }

  // --- Student Progress Overview (additive) ---

  Future<List<StudentProgressModel>> fetchStudentProgress() async {
    final response = await _api.get(ApiConstants.adminStudentProgress);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => StudentProgressModel.fromJson(json as Map<String, dynamic>)).toList();
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\services\admin_service.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\services\admin_service.dart"

# --- frontend/lib/screens/admin/student_progress_screen.dart ---
$content = @'
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_service.dart';

/// Admin-only: every student's lessons completed, average quiz score,
/// and current learning streak in one place. Read-only overview - no
/// editing happens here, per-student changes still happen wherever
/// they already happen (class/section assignment, etc.).
class StudentProgressScreen extends StatefulWidget {
  const StudentProgressScreen({super.key});

  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _searchController = TextEditingController();

  List<StudentProgressModel> _all = [];
  List<StudentProgressModel> _filtered = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _all = await _adminService.fetchStudentProgress();
      _applyFilter();
    } catch (e) {
      _error = 'Could not load student progress.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _all
          : _all.where((s) => s.name.toLowerCase().contains(query) || s.email.toLowerCase().contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Student Progress'),
        elevation: 0,
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textPrimary,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
                    ],
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by name or email...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          ),
        ),
        const SizedBox(height: 8),
        Text('${_filtered.length} student${_filtered.length == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        if (_filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No students found.', style: TextStyle(color: AppColors.textSecondary))),
          )
        else
          ..._filtered.map(_studentCard),
      ],
    );
  }

  Widget _studentCard(StudentProgressModel s) {
    final classSection = [s.classValue, s.section].where((v) => v.isNotEmpty).join(' - ');
    final percent = (s.completionPercent * 100).clamp(0, 100);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.purpleLight,
                child: Text(
                  s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(s.email, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    if (classSection.isNotEmpty)
                      Text(classSection, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (s.currentStreak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('\u{1F525}', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text('${s.currentStreak}d', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.orange)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Lessons completed', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text('${s.lessonsCompleted}/${s.totalLessons} (${percent.toStringAsFixed(0)}%)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: s.completionPercent.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: AppColors.pageBackground,
                        color: AppColors.purple,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.quiz_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                s.averageQuizScore != null ? 'Avg quiz score: ${s.averageQuizScore!.toStringAsFixed(0)}%' : 'No quiz attempts yet',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\screens\admin\student_progress_screen.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\screens\admin\student_progress_screen.dart"

# --- frontend/lib/screens/profile/profile_screen.dart ---
$content = @'
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'edit_profile_screen.dart';
import '../badges/my_badges_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../leaderboard/manage_students_screen.dart';
import '../certificates/my_certificates_screen.dart';
import '../courses/admin_course_management_screen.dart';
import '../courses/teacher_lessons_screen.dart';
import '../admin/student_progress_screen.dart';

/// Profile tab: shows the logged-in user's info and a logout button.
/// UI redesign only â€” AuthProvider.logout() and the navigation after it
/// are exactly what they were before.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(color: AppColors.purpleLight, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      (user?.name.isNotEmpty == true ? user!.name[0] : '?').toUpperCase(),
                      style: const TextStyle(fontSize: 34, color: AppColors.purple, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(user?.name ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.purpleLight, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    (user?.role ?? '-').toUpperCase(),
                    style: const TextStyle(color: AppColors.purple, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),

          const SizedBox(height: 20),

          _ProfileMenuTile(
            icon: Icons.edit_outlined,
            label: 'Edit Profile',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
            },
          ).animate().fadeIn(duration: 250.ms, delay: 100.ms),
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.bar_chart_rounded,
            label: 'Quiz Analytics',
            onTap: () => context.push('/quiz-analytics'),
          ).animate().fadeIn(duration: 250.ms, delay: 130.ms),
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.auto_awesome_rounded,
            label: 'AI Quiz Generator',
            onTap: () => context.push('/ai-quiz-generator'),
          ).animate().fadeIn(duration: 250.ms, delay: 145.ms),
          _ProfileMenuTile(
            icon: Icons.leaderboard_rounded,
            label: 'Leaderboard',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
            },
          ).animate().fadeIn(duration: 250.ms, delay: 130.ms),
          if (auth.currentUser?.role == 'student') ...[
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.video_camera_front_rounded,
              label: 'Live Classes',
              onTap: () => context.push('/student-live-classes'),
            ).animate().fadeIn(duration: 250.ms, delay: 147.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.emoji_events_rounded,
              label: 'My Badges',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBadgesScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 160.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.workspace_premium_rounded,
              label: 'My Certificates',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCertificatesScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 165.ms),
          ],
          if (auth.currentUser?.role == 'teacher') ...[
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.assignment_rounded,
              label: 'My Assignments',
              onTap: () => context.push('/my-assignments'),
            ).animate().fadeIn(duration: 250.ms, delay: 148.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.video_camera_front_rounded,
              label: 'My Live Classes',
              onTap: () => context.push('/my-live-classes'),
            ).animate().fadeIn(duration: 250.ms, delay: 149.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.library_books_rounded,
              label: 'Manage Lessons',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherLessonsScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 150.ms),
          ],
          if (auth.currentUser?.role == 'admin') ...[
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.admin_panel_settings_rounded,
              label: 'Admin Panel',
              onTap: () => context.push('/admin-dashboard'),
            ).animate().fadeIn(duration: 250.ms, delay: 150.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.groups_rounded,
              label: 'Manage Students',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageStudentsScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 155.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.insights_rounded,
              label: 'Student Progress',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentProgressScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 156.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.workspace_premium_rounded,
              label: 'All Certificates',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCertificatesScreen(mode: CertificateListMode.admin)));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 156.ms),
            const SizedBox(height: 12),
            _ProfileMenuTile(
              icon: Icons.library_books_rounded,
              label: 'Course Management',
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCourseManagementScreen()));
              },
            ).animate().fadeIn(duration: 250.ms, delay: 157.ms),
          ],
          const SizedBox(height: 12),
          _ProfileMenuTile(
            icon: Icons.logout_rounded,
            label: 'Logout',
            color: AppColors.error,
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Are you sure?'),
                  content: const Text('You will be logged out of your account.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('No'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Yes', style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await context.read<AuthProvider>().logout();
              if (context.mounted) context.go('/login');
            },
          ).animate().fadeIn(duration: 250.ms, delay: 160.ms),
        ],
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ProfileMenuTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.textPrimary;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 22),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w600, fontSize: 15))),
              Icon(Icons.chevron_right_rounded, color: tint.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\screens\profile\profile_screen.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\screens\profile\profile_screen.dart"

Write-Host ""
Write-Host "All files written successfully." -ForegroundColor Green