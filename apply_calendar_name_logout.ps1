$Root = "C:\Users\ABC\Desktop\ai_tutor_app"

New-Item -ItemType Directory -Force -Path "$Root\backend\internal\streak" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\core\constants" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\providers" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\screens\profile" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\screens\quiz" | Out-Null
New-Item -ItemType Directory -Force -Path "$Root\frontend\lib\services" | Out-Null

# --- backend/internal/streak/repository.go ---
$content = @'
// Package streak computes a real "Learning Streak" from actual student
// activity (lesson completions, quiz attempts, AI Tutor chats) - no
// fabricated numbers. Any of those three actions marks "today" as active
// for that user.
package streak

import (
	"database/sql"
	"time"
)

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// RecordActivity marks today as an active day for userID. Idempotent -
// safe to call many times in the same day.
func (r *Repository) RecordActivity(userID int) error {
	_, err := r.db.Exec(`
		INSERT INTO user_activity_days (user_id, activity_date)
		VALUES ($1, CURRENT_DATE)
		ON CONFLICT (user_id, activity_date) DO NOTHING`, userID)
	return err
}

func (r *Repository) allDatesDesc(userID int) ([]time.Time, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1
		ORDER BY activity_date DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var dates []time.Time
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		dates = append(dates, d)
	}
	return dates, rows.Err()
}

// GetCurrentStreak returns the number of consecutive active days ending
// today or yesterday. Returns 0 if the most recent activity was more
// than 1 day ago (streak broken).
func (r *Repository) GetCurrentStreak(userID int) (int, error) {
	dates, err := r.allDatesDesc(userID)
	if err != nil {
		return 0, err
	}
	if len(dates) == 0 {
		return 0, nil
	}

	today := truncateToDate(time.Now())
	daysSinceRecent := int(today.Sub(dates[0]).Hours() / 24)
	if daysSinceRecent > 1 {
		return 0, nil
	}

	streakCount := 1
	for i := 1; i < len(dates); i++ {
		diff := int(dates[i-1].Sub(dates[i]).Hours() / 24)
		if diff == 1 {
			streakCount++
		} else {
			break
		}
	}
	return streakCount, nil
}

// GetLongestStreak scans the user's full activity history for the
// longest run of consecutive active days ever, not just the current one.
func (r *Repository) GetLongestStreak(userID int) (int, error) {
	dates, err := r.allDatesDesc(userID)
	if err != nil {
		return 0, err
	}
	if len(dates) == 0 {
		return 0, nil
	}

	longest := 1
	current := 1
	for i := 1; i < len(dates); i++ {
		diff := int(dates[i-1].Sub(dates[i]).Hours() / 24)
		if diff == 1 {
			current++
			if current > longest {
				longest = current
			}
		} else {
			current = 1
		}
	}
	return longest, nil
}

// GetActiveDaysThisWeek returns how many distinct days (0-7) the user has
// been active since the start of the current calendar week.
func (r *Repository) GetActiveDaysThisWeek(userID int) (int, error) {
	var count int
	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= date_trunc('week', CURRENT_DATE)`, userID,
	).Scan(&count)
	return count, err
}

// GetWeeklyActivity returns a 7-element bool array for the last 7 days
// (oldest first, today last), true if the user was active that day - for
// the "weekly streak graph".
func (r *Repository) GetWeeklyActivity(userID int) ([]bool, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= CURRENT_DATE - INTERVAL '6 days'`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	activeDates := map[string]bool{}
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		activeDates[d.Format("2006-01-02")] = true
	}

	result := make([]bool, 7)
	today := truncateToDate(time.Now())
	for i := 0; i < 7; i++ {
		day := today.AddDate(0, 0, -6+i)
		result[i] = activeDates[day.Format("2006-01-02")]
	}
	return result, nil
}

// GetActivityHeatmap returns one entry per day for the last `days` days
// (oldest first), for a GitHub-style learning calendar.
func (r *Repository) GetActivityHeatmap(userID, days int) ([]HeatmapDay, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= CURRENT_DATE - ($2 || ' days')::interval`, userID, days-1)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	activeDates := map[string]bool{}
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		activeDates[d.Format("2006-01-02")] = true
	}

	today := truncateToDate(time.Now())
	result := make([]HeatmapDay, days)
	for i := 0; i < days; i++ {
		day := today.AddDate(0, 0, -(days-1)+i)
		key := day.Format("2006-01-02")
		result[i] = HeatmapDay{Date: key, Active: activeDates[key]}
	}
	return result, nil
}

// --- Learning Calendar month view (additive) ---
//
// Unlike GetActivityHeatmap (a rolling "last N days" window that always
// ends today), this returns every active date within one specific
// calendar month - regardless of month/year - so the Learning Calendar
// screen can page back through past months' full history.
func (r *Repository) GetActiveDatesForMonth(userID, year, month int) ([]string, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1
			AND activity_date >= make_date($2, $3, 1)
			AND activity_date < (make_date($2, $3, 1) + INTERVAL '1 month')`,
		userID, year, month)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var dates []string
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		dates = append(dates, d.Format("2006-01-02"))
	}
	return dates, rows.Err()
}

func truncateToDate(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}

// GetCurrentStreakWithStartDate is like GetCurrentStreak, but also
// returns the date the current unbroken run started. Added (additive -
// GetCurrentStreak itself is untouched, so no other caller is affected)
// for the "study streak reward logic" QA fix in xp/service.go: without
// a stable per-run anchor, a milestone reward's dedup key ("streak-
// milestone-1") stayed the same forever, so a student who broke their
// streak and later built a fresh 7-day run again could never be
// rewarded for it a second time - the run's start date makes each
// distinct streak run's key unique.
func (r *Repository) GetCurrentStreakWithStartDate(userID int) (int, time.Time, error) {
	dates, err := r.allDatesDesc(userID)
	if err != nil {
		return 0, time.Time{}, err
	}
	if len(dates) == 0 {
		return 0, time.Time{}, nil
	}

	today := truncateToDate(time.Now())
	daysSinceRecent := int(today.Sub(dates[0]).Hours() / 24)
	if daysSinceRecent > 1 {
		return 0, time.Time{}, nil
	}

	streakCount := 1
	startDate := dates[0]
	for i := 1; i < len(dates); i++ {
		diff := int(dates[i-1].Sub(dates[i]).Hours() / 24)
		if diff == 1 {
			streakCount++
			startDate = dates[i]
		} else {
			break
		}
	}
	return streakCount, startDate, nil
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\streak\repository.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\streak\repository.go"

# --- backend/internal/streak/service.go ---
$content = @'
package streak

// Service exposes streak computation. RecordActivity is called by other
// packages (progress, quiz, ai) whenever the student does something -
// this package doesn't know or care which action, it just marks the day.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) RecordActivity(userID int) error {
	return s.repo.RecordActivity(userID)
}

// HeatmapDay is one cell in the learning calendar heatmap.
type HeatmapDay struct {
	Date   string `json:"date"`
	Active bool   `json:"active"`
}

// Summary is the full response for GET /api/streak.
type Summary struct {
	CurrentStreak      int          `json:"current_streak"`
	LongestStreak      int          `json:"longest_streak"`
	ActiveDaysThisWeek int          `json:"active_days_this_week"`
	WeeklyActivity     []bool       `json:"weekly_activity"`
	Heatmap            []HeatmapDay `json:"heatmap"`
}

func (s *Service) GetSummary(userID int) (*Summary, error) {
	currentStreak, err := s.repo.GetCurrentStreak(userID)
	if err != nil {
		return nil, err
	}
	longestStreak, err := s.repo.GetLongestStreak(userID)
	if err != nil {
		return nil, err
	}
	weekCount, err := s.repo.GetActiveDaysThisWeek(userID)
	if err != nil {
		return nil, err
	}
	weeklyActivity, err := s.repo.GetWeeklyActivity(userID)
	if err != nil {
		return nil, err
	}
	heatmap, err := s.repo.GetActivityHeatmap(userID, 35)
	if err != nil {
		return nil, err
	}

	return &Summary{
		CurrentStreak:      currentStreak,
		LongestStreak:      longestStreak,
		ActiveDaysThisWeek: weekCount,
		WeeklyActivity:     weeklyActivity,
		Heatmap:            heatmap,
	}, nil
}

// --- Learning Calendar month view (additive) ---

// MonthCalendar is the response for GET /api/streak/calendar.
type MonthCalendar struct {
	Year        int      `json:"year"`
	Month       int      `json:"month"`
	ActiveDates []string `json:"active_dates"`
}

func (s *Service) GetMonthCalendar(userID, year, month int) (*MonthCalendar, error) {
	dates, err := s.repo.GetActiveDatesForMonth(userID, year, month)
	if err != nil {
		return nil, err
	}
	return &MonthCalendar{Year: year, Month: month, ActiveDates: dates}, nil
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\streak\service.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\streak\service.go"

# --- backend/internal/streak/handler.go ---
$content = @'
package streak

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// GetSummary handles GET /api/streak.
func (h *Handler) GetSummary(c *gin.Context) {
	userID := c.GetInt("user_id")

	summary, err := h.service.GetSummary(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load streak")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Streak fetched", summary)
}

// --- Learning Calendar month view (additive) ---

// GetMonthCalendar handles GET /api/streak/calendar?year=2026&month=7.
// Defaults to the current year/month if not provided.
func (h *Handler) GetMonthCalendar(c *gin.Context) {
	userID := c.GetInt("user_id")
	now := time.Now()

	year, err := strconv.Atoi(c.DefaultQuery("year", strconv.Itoa(now.Year())))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid year")
		return
	}
	month, err := strconv.Atoi(c.DefaultQuery("month", strconv.Itoa(int(now.Month()))))
	if err != nil || month < 1 || month > 12 {
		utils.RespondError(c, http.StatusBadRequest, "Invalid month")
		return
	}

	calendar, err := h.service.GetMonthCalendar(userID, year, month)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load calendar")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Calendar fetched", calendar)
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\streak\handler.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\streak\handler.go"

# --- backend/internal/streak/routes.go ---
$content = @'
package streak

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches GET /api/streak.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.GET("/streak", authMiddleware, handler.GetSummary)
	// Learning Calendar month view (additive)
	router.GET("/streak/calendar", authMiddleware, handler.GetMonthCalendar)
}
'@
[System.IO.File]::WriteAllText("$Root\backend\internal\streak\routes.go", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: backend\internal\streak\routes.go"

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

# --- frontend/lib/screens/profile/edit_profile_screen.dart ---
$content = @'
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';

/// Edit Profile - name, email, and password can all be updated; the
/// backend's /api/users/profile endpoint already supports name+email
/// together (see UserService.updateProfile), name just wasn't wired up
/// to an editable field here before.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();
  final _nameFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _originalName = '';
  String _originalEmail = '';
  bool _loadingEmail = true;
  bool _savingName = false;
  bool _savingEmail = false;
  bool _changingPassword = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _originalName = context.read<AuthProvider>().currentUser?.name ?? '';
    _nameController = TextEditingController(text: _originalName);
    _emailController = TextEditingController();
    _loadCurrentEmail();
  }

  // AuthProvider's cached user only carries id/name/role (that's all the
  // login response returns) - the real email lives in the fuller
  // GET /api/auth/profile response, so we fetch that fresh here.
  Future<void> _loadCurrentEmail() async {
    try {
      final data = await _authService.fetchProfile();
      final email = data['email'] as String? ?? '';
      if (mounted) {
        setState(() {
          _originalEmail = email;
          _emailController.text = email;
          _loadingEmail = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _nameController.text.trim() != _originalName ||
      _emailController.text.trim() != _originalEmail ||
      _currentPasswordController.text.isNotEmpty ||
      _newPasswordController.text.isNotEmpty ||
      _confirmPasswordController.text.isNotEmpty;

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Leave without saving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _saveName() async {
    if (!_nameFormKey.currentState!.validate()) return;
    if (_nameController.text.trim() == _originalName) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update name?'),
        content: Text('Change your name to ${_nameController.text.trim()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _savingName = true);
    try {
      final newName = _nameController.text.trim();
      await _userService.updateProfile(name: newName, email: _originalEmail);
      if (!mounted) return;
      await context.read<AuthProvider>().updateLocalName(newName);
      if (mounted) setState(() => _originalName = newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name updated successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _saveEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    if (_emailController.text.trim() == _originalEmail) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update email?'),
        content: Text('Change your email to ${_emailController.text.trim()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    // QA fix ("Missing mounted checks after async operations" / "Safe
    // BuildContext usage"): context.read<AuthProvider>() below used to
    // run right after the dialog's await with no mounted guard.
    if (!mounted) return;

    setState(() => _savingEmail = true);
    try {
      await _userService.updateProfile(name: _originalName, email: _emailController.text.trim());
      if (mounted) setState(() => _originalEmail = _emailController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email updated successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _savingEmail = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password?'),
        content: const Text('You will need to use the new password next time you log in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _changingPassword = true);
    try {
      await _userService.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // QA fix ("Safe BuildContext usage"): mounted IS checked
        // immediately before this Navigator.pop, but Flutter's analyzer
        // has a known blind spot for `mounted` checks inside a
        // PopScope callback closure - it can't always verify the guard
        // covers the context use that follows it in this shape. This is
        // a verified analyzer false-positive, not an unguarded use.
        final shouldDiscard = await _confirmDiscard();
        if (!mounted) return;
        if (shouldDiscard) {
          // ignore: use_build_context_synchronously
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionCard(
              title: 'Name',
              child: Form(
                key: _nameFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Full name'),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Name is required';
                        if (v.length < 2) return 'Name is too short';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _savingName ? null : _saveName,
                      child: _savingName
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save Name'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Email',
              child: _loadingEmail
                  ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  : Form(
                key: _emailFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Email address'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Email is required';
                        final regex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
                        if (!regex.hasMatch(v)) return 'Enter a valid email address';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _savingEmail ? null : _saveEmail,
                      child: _savingEmail
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save Email'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Change Password',
              child: Form(
                key: _passwordFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: _obscureCurrent,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Current password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty) ? 'Enter your current password' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'New password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Enter a new password';
                        if (value.length < 6) return 'Password must be at least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Confirm new password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (value) {
                        if (value != _newPasswordController.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _changingPassword ? null : _changePassword,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
                      child: _changingPassword
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Change Password', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\screens\profile\edit_profile_screen.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\screens\profile\edit_profile_screen.dart"

# --- frontend/lib/providers/auth_provider.dart ---
$content = @'
import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Holds authentication state (token, current user, loading/error flags)
/// and exposes the actions screens call: register, login, logout, restore.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final StorageService _storage = StorageService();

  AuthStatus status = AuthStatus.unknown;
  UserModel? currentUser;
  bool isLoading = false;
  String? errorMessage;

  // QA fix ("Router rebuild issue"): app_router.dart used to pass this
  // whole AuthProvider as GoRouter's refreshListenable, so EVERY
  // notifyListeners() call here - including ones that only change
  // isLoading for a button spinner, with status untouched - triggered a
  // full router redirect re-evaluation and route rebuild. statusNotifier
  // is a dedicated ValueNotifier that only fires when `status` itself
  // actually changes (ValueNotifier's built-in equality check), and
  // app_router.dart now listens to this instead of the whole provider.
  final ValueNotifier<AuthStatus> statusNotifier = ValueNotifier(AuthStatus.unknown);

  void _setStatus(AuthStatus newStatus) {
    status = newStatus;
    statusNotifier.value = newStatus;
  }

  @override
  void dispose() {
    statusNotifier.dispose();
    super.dispose();
  }

  // --- Editable name (additive) ---
  //
  // Updates the cached user (so the rest of the app reflects the new
  // name immediately, no re-login needed) and persists it to secure
  // storage, same as tryAutoLogin reads it back from.
  Future<void> updateLocalName(String name) async {
    if (currentUser != null) {
      currentUser = UserModel(id: currentUser!.id, name: name, role: currentUser!.role);
      await _storage.setString(AppConstants.keyUserName, name);
      notifyListeners();
    }
  }

  /// Called once at app startup to check for a previously saved session.
  Future<void> tryAutoLogin() async {
    final token = await _storage.getString(AppConstants.keyAuthToken);
    final userId = await _storage.getInt(AppConstants.keyUserId);
    final userName = await _storage.getString(AppConstants.keyUserName);
    final userRole = await _storage.getString(AppConstants.keyUserRole);

    if (token != null && userId != null && userName != null && userRole != null) {
      currentUser = UserModel(id: userId, name: userName, role: userRole);
      _setStatus(AuthStatus.authenticated);
    } else {
      _setStatus(AuthStatus.unauthenticated);
    }
    notifyListeners();
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    return _runGuarded(() async {
      await _authService.register(name: name, email: email, password: password);
    });
  }

  /// Submits a teacher application - the account starts "pending" and
  /// can't log in until an admin approves it.
  Future<bool> applyAsTeacher({
    required String name,
    required String email,
    required String password,
    String phone = '',
    String qualification = '',
    String experience = '',
    String subjects = '',
    String bio = '',
  }) async {
    return _runGuarded(() async {
      await _authService.applyAsTeacher(
        name: name,
        email: email,
        password: password,
        phone: phone,
        qualification: qualification,
        experience: experience,
        subjects: subjects,
        bio: bio,
      );
    });
  }

  Future<bool> login({required String email, required String password}) async {
    return _runGuarded(() async {
      final result = await _authService.login(email: email, password: password);

      await _storage.setString(AppConstants.keyAuthToken, result.token);
      await _storage.setInt(AppConstants.keyUserId, result.user.id);
      await _storage.setString(AppConstants.keyUserName, result.user.name);
      await _storage.setString(AppConstants.keyUserRole, result.user.role);

      currentUser = result.user;
      _setStatus(AuthStatus.authenticated);
    });
  }

  Future<void> logout() async {
    await _storage.clearAll();
    currentUser = null;
    _setStatus(AuthStatus.unauthenticated);
    notifyListeners();
  }

  /// Runs an async action with consistent loading/error state handling,
  /// so screens don't need to repeat try/catch/setState boilerplate.
  Future<bool> _runGuarded(Future<void> Function() action) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await action();
      isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      isLoading = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      isLoading = false;
      errorMessage = 'Something went wrong. Please try again.';
      notifyListeners();
      return false;
    }
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\providers\auth_provider.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\providers\auth_provider.dart"

# --- frontend/lib/core/constants/api_constants.dart ---
$content = @'
/// Centralized API configuration so base URLs and endpoint paths
/// only ever need to change in one place.
class ApiConstants {
  ApiConstants._();

  /// Android emulator maps 10.0.2.2 to the host machine's localhost.
  /// - Physical device / real backend: replace with your machine's LAN IP
  ///   or your deployed Render URL, e.g. https://your-app.onrender.com
  /// - iOS simulator: use http://localhost:8080
  static const String baseUrl = 'http://192.168.1.13:8080/api';

  // --- Day 1: Auth ---
  static const String register = '/auth/register';
  static const String badgesMine = '/badges/mine';
  static String badgesForStudent(int studentId) => '/badges/student/$studentId';
  static const String xpMine = '/xp/mine';
  static String leaderboard({String period = 'overall', String? classFilter, String? section}) {
    var path = '/leaderboard?period=$period';
    if (classFilter != null && classFilter.isNotEmpty) path += '&class=$classFilter';
    if (section != null && section.isNotEmpty) path += '&section=$section';
    return path;
  }
  static String assignClassSection(int studentId) => '/admin/students/$studentId/class-section';
  static const String adminStudents = '/admin/students';
  static const String certificatesMine = '/certificates/mine';
  static const String certificatesTeacher = '/certificates/teacher';
  static const String certificatesAll = '/certificates/all';
  static String certificate(int id) => '/certificates/$id';
  static String adminCourses({String? search, int? categoryId, String? status}) {
    var path = '/admin/courses?';
    final params = <String>[];
    if (search != null && search.isNotEmpty) params.add('search=${Uri.encodeQueryComponent(search)}');
    if (categoryId != null) params.add('category_id=$categoryId');
    if (status != null && status.isNotEmpty) params.add('status=$status');
    return path + params.join('&');
  }
  static String course(int id) => '/subjects/$id';
  static String coursePublish(int id) => '/subjects/$id/publish';
  static String courseUnpublish(int id) => '/subjects/$id/unpublish';
  static String categoryUpdate(int id) => '/categories/$id';
  static const String lessonsCreate = '/lessons';
  static String lessonsReorder(int subjectId) => '/subjects/$subjectId/lessons/reorder';
  static String lessonUploadVideo(int id) => '/lessons/$id/upload-video';
  static String lessonUploadPdf(int id) => '/lessons/$id/upload-pdf';
  static String lessonUploadAssignment(int id) => '/lessons/$id/upload-assignment';
  // Lesson Resource Management (additive)
  static String lessonPublish(int id) => '/lessons/$id/publish';
  static String lessonUnpublish(int id) => '/lessons/$id/unpublish';
  static const String teacherApply = '/auth/teacher/apply';
  static const String login = '/auth/login';
  static const String profile = '/auth/profile';
  static const String updateProfile = '/users/profile';
  static const String changePassword = '/users/change-password';

  // --- Day 2: Course & Learning Management ---
  static const String categories = '/categories';
  static String categorySubjects(int categoryId) => '/categories/$categoryId/subjects';
  static const String subjects = '/subjects';
  static String subjectById(int subjectId) => '/subjects/$subjectId';
  static String subjectLessons(int subjectId) => '/subjects/$subjectId/lessons';
  static String lessonById(int lessonId) => '/lessons/$lessonId';
  static String lessonNotes(int lessonId) => '/lessons/$lessonId/notes';
  static String lessonAiContent(int lessonId) => '/lessons/$lessonId/ai-content';
  static const String search = '/search';

  // --- Progress tracking ---
  static String markLessonComplete(int lessonId) => '/progress/lessons/$lessonId/complete';
  static String subjectProgress(int subjectId) => '/progress/subjects/$subjectId';

  // --- AI Tutor ---
  static const String aiChat = '/ai/chat';
  static const String aiSessions = '/ai/sessions';
  static String aiSession(int id) => '/ai/sessions/$id';
  static const String aiRecommendations = '/ai/recommendations';

  // --- YouTube video integration ---
  static String lessonVideos(int lessonId) => '/lessons/$lessonId/videos';
  static String lessonVideoProgress(int lessonId) => '/lessons/$lessonId/videos/progress';
  static const String videoSearch = '/videos/search';

  // --- Quiz & Assessment ---
  static String submitLessonQuizAttempt(int lessonId) => '/quiz/lessons/$lessonId/attempt';
  static const String submitFreeformQuizAttempt = '/quiz/freeform/attempt';
  static const String quizAttempts = '/quiz/attempts';
  static String quizAttempt(int id) => '/quiz/attempts/$id';
  static const String quizAnalytics = '/quiz/analytics';
  static const String quizGenerate = '/quiz/generate';

  // --- Learning Streak ---
  static const String streak = '/streak';
  // Learning Calendar month view (additive)
  static String streakCalendar(int year, int month) => '/streak/calendar?year=$year&month=$month';

  // --- Admin Panel ---
  static const String adminDashboard = '/admin/dashboard';
  static const String adminPendingTeachers = '/auth/admin/teachers/pending';
  static String adminApproveTeacher(int id) => '/auth/admin/teachers/$id/approve';
  // Student Progress Overview (additive)
  static const String adminStudentProgress = '/admin/students/progress';
  static String adminRejectTeacher(int id) => '/auth/admin/teachers/$id/reject';

  // --- Assignments ---
  static const String assignments = '/assignments';
  static String assignment(int id) => '/assignments/$id';
  static String assignmentPublish(int id) => '/assignments/$id/publish';
  static String assignmentUnpublish(int id) => '/assignments/$id/unpublish';
  static String assignmentClose(int id) => '/assignments/$id/close';
  static String assignmentArchive(int id) => '/assignments/$id/archive';
  static const String assignmentGenerateAI = '/assignments/generate-ai';
  static const String myAssignments = '/assignments/mine';
  static const String teacherAssignmentAnalytics = '/assignments/analytics';
  static String assignmentSubmissions(int id) => '/assignments/$id/submissions';
  static String reviewSubmission(int id) => '/assignments/submissions/$id/review';
  static String assignmentDraft(int id) => '/assignments/$id/draft';
  static String assignmentSubmit(int id) => '/assignments/$id/submit';
  static String mySubmission(int id) => '/assignments/$id/my-submission';
  static String retryEvaluation(int submissionId) => '/assignments/submissions/$submissionId/retry-evaluation';
  static const String assignmentsForStudent = '/assignments/for-student';
  static String subjectAssignments(int subjectId) => '/subjects/$subjectId/assignments';
  static const String adminAssignments = '/admin/assignments';
  static const String adminAssignmentAnalytics = '/admin/assignments/analytics';

  // --- Live Classes (Phase 1: scheduling only, no video) ---
  static const String liveClasses = '/live-classes';
  static String liveClass(int id) => '/live-classes/$id';
  static String liveClassCancel(int id) => '/live-classes/$id/cancel';
  static String liveClassComplete(int id) => '/live-classes/$id/complete';
  static const String myLiveClasses = '/live-classes/mine';
  static const String liveClassesForStudent = '/live-classes/for-student';
  static const String adminLiveClasses = '/admin/live-classes';
  static String adminLiveClassCancel(int id) => '/admin/live-classes/$id/cancel';
  static String liveClassCheckIn(int id) => '/live-classes/$id/check-in';
  static String liveClassMyAttendance(int id) => '/live-classes/$id/my-attendance';
  static String liveClassAttendance(int id) => '/live-classes/$id/attendance';
  static const String liveClassAttendanceSummary = '/live-classes/attendance-summary';
  static String liveClassStart(int id) => '/live-classes/$id/start';
  static String liveClassJoin(int id) => '/live-classes/$id/join';
  static String liveClassEnd(int id) => '/live-classes/$id/end';
  static String liveClassMeetingStatus(int id) => '/live-classes/$id/meeting-status';
  static String liveClassResources(int id) => '/live-classes/$id/resources';
  static String liveClassResourceDelete(int classId, int resourceId) => '/live-classes/$classId/resources/$resourceId';
  static String liveClassMute(int id, String identity) => '/live-classes/$id/mute/$identity';
  static String liveClassRemove(int id, String identity) => '/live-classes/$id/remove/$identity';
  static String liveClassMuteAll(int id) => '/live-classes/$id/mute-all';
  static String liveClassLock(int id) => '/live-classes/$id/lock';
  static String liveClassUnlock(int id) => '/live-classes/$id/unlock';

  // --- Notifications ---
  static const String notifications = '/notifications';
  static const String notificationUnreadCount = '/notifications/unread-count';
  static String notificationRead(int id) => '/notifications/$id/read';
  static const String notificationReadAll = '/notifications/read-all';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// Resolves a possibly-relative media path (e.g. "/static/notes/x.pdf",
  /// stored in the DB so it works on any host) into a full URL using the
  /// same host as [baseUrl]. Already-absolute URLs (http/https) pass through
  /// unchanged, so externally hosted media still works too.
  static String resolveMediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final origin = baseUrl.replaceAll('/api', '');
    return '$origin$path';
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\core\constants\api_constants.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\core\constants\api_constants.dart"

# --- frontend/lib/services/streak_service.dart ---
$content = @'
import '../core/constants/api_constants.dart';
import 'api_service.dart';

class HeatmapDayModel {
  final String date;
  final bool active;
  HeatmapDayModel({required this.date, required this.active});

  factory HeatmapDayModel.fromJson(Map<String, dynamic> json) {
    return HeatmapDayModel(date: json['date'] as String? ?? '', active: json['active'] as bool? ?? false);
  }
}

class StreakSummary {
  final int currentStreak;
  final int longestStreak;
  final int activeDaysThisWeek;
  final List<bool> weeklyActivity;
  final List<HeatmapDayModel> heatmap;

  StreakSummary({
    required this.currentStreak,
    required this.longestStreak,
    required this.activeDaysThisWeek,
    required this.weeklyActivity,
    required this.heatmap,
  });

  factory StreakSummary.fromJson(Map<String, dynamic> json) {
    return StreakSummary(
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      activeDaysThisWeek: json['active_days_this_week'] as int? ?? 0,
      weeklyActivity: (json['weekly_activity'] as List<dynamic>? ?? []).map((e) => e as bool).toList(),
      heatmap: (json['heatmap'] as List<dynamic>? ?? [])
          .map((e) => HeatmapDayModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Talks to /api/streak - a real streak computed from actual activity
/// (lesson completions, quiz attempts, AI Tutor chats), never a fake number.
class StreakService {
  final ApiService _api = ApiService();

  Future<StreakSummary> fetchSummary() async {
    final response = await _api.get(ApiConstants.streak);
    return StreakSummary.fromJson(response['data'] as Map<String, dynamic>);
  }

  // --- Learning Calendar month view (additive) ---

  /// Returns the set of active dates ("yyyy-MM-dd") for one specific
  /// calendar month - lets the Learning Calendar page back through past
  /// months, unlike the rolling "last 35 days" heatmap above.
  Future<Set<String>> fetchMonthCalendar(int year, int month) async {
    final response = await _api.get(ApiConstants.streakCalendar(year, month));
    final data = response['data'] as Map<String, dynamic>;
    final dates = (data['active_dates'] as List<dynamic>? ?? []).map((e) => e as String);
    return dates.toSet();
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\services\streak_service.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\services\streak_service.dart"

# --- frontend/lib/screens/quiz/progress_dashboard_screen.dart ---
$content = @'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/quiz_attempt_model.dart';
import '../../models/subject_model.dart';
import '../../services/quiz_service.dart';
import '../../services/streak_service.dart';
import '../../services/subject_service.dart';
import '../../widgets/skeleton_box.dart';

/// Full Progress Dashboard: overall progress, real Learning Streak
/// (current + longest + weekly graph), study hours, course-wise progress,
/// quiz performance, a weekly performance trend, a learning calendar
/// heatmap, rule-based achievements, AI insights (strength/weakness from
/// real data, no fabricated "predicted score"), and a composite Learning
/// Health Score built from real signals.
class ProgressDashboardScreen extends StatefulWidget {
  const ProgressDashboardScreen({super.key});

  @override
  State<ProgressDashboardScreen> createState() => _ProgressDashboardScreenState();
}

class _ProgressDashboardScreenState extends State<ProgressDashboardScreen> {
  final SubjectService _subjectService = SubjectService();
  final QuizService _quizService = QuizService();
  final StreakService _streakService = StreakService();

  List<SubjectModel> _subjects = [];
  QuizAnalyticsModel? _analytics;
  StreakSummary? _streak;
  bool _isLoading = true;
  String? _error;

  // --- Learning Calendar month view (additive) ---
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Set<String> _calendarActiveDates = {};
  bool _loadingCalendar = false;

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _loadCalendarMonth(_calendarMonth);
  }

  Future<void> _loadCalendarMonth(DateTime month) async {
    setState(() => _loadingCalendar = true);
    try {
      final dates = await _streakService.fetchMonthCalendar(month.year, month.month);
      if (mounted) setState(() => _calendarActiveDates = dates);
    } catch (e) {
      // Keep whatever was showing before; the calendar card just won't
      // update for this month if the request fails.
    }
    if (mounted) setState(() => _loadingCalendar = false);
  }

  void _goToMonth(int monthDelta) {
    final next = DateTime(_calendarMonth.year, _calendarMonth.month + monthDelta);
    final now = DateTime.now();
    if (next.year > now.year || (next.year == now.year && next.month > now.month)) {
      return; // no browsing into the future
    }
    setState(() => _calendarMonth = next);
    _loadCalendarMonth(next);
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _subjects = await _subjectService.fetchAllSubjects();
      _analytics = await _quizService.fetchAnalytics();
      _streak = await _streakService.fetchSummary();
    } catch (e) {
      _error = 'Could not load your progress. Please try again.';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  int get _totalLessonsCompleted => _subjects.fold(0, (sum, s) => sum + s.completedLessons);
  int get _totalLessons => _subjects.fold(0, (sum, s) => sum + s.lessonCount);
  double get _totalCompletedHours => _subjects.fold(0.0, (sum, s) => sum + s.completedHours);
  int get _coursesCompleted => _subjects.where((s) => s.progressPercentage >= 100).length;
  double get _overallProgress => _totalLessons == 0 ? 0 : (_totalLessonsCompleted / _totalLessons) * 100;

  List<SubjectModel> get _inProgressSubjects =>
      _subjects.where((s) => s.progressPercentage > 0 && s.progressPercentage < 100).toList()
        ..sort((a, b) => b.progressPercentage.compareTo(a.progressPercentage));

  SubjectAccuracyModel? get _strongestSubject {
    final withAttempts = (_analytics?.bySubject ?? []).where((s) => s.attempts > 0).toList();
    if (withAttempts.isEmpty) return null;
    withAttempts.sort((a, b) => b.accuracy.compareTo(a.accuracy));
    return withAttempts.first;
  }

  SubjectAccuracyModel? get _weakestSubject {
    final withAttempts = (_analytics?.bySubject ?? []).where((s) => s.attempts > 0).toList();
    if (withAttempts.isEmpty) return null;
    withAttempts.sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return withAttempts.first;
  }

  /// Composite score from real signals only (Consistency from streak,
  /// Accuracy from quiz analytics, Engagement from attempt volume). This
  /// is our own defined formula, not a scientific measurement - shown
  /// transparently with its breakdown so it's never mistaken for one.
  Map<String, double> get _healthBreakdown {
    final consistency = ((_streak?.activeDaysThisWeek ?? 0) / 7 * 100).clamp(0.0, 100.0);
    final accuracy = (_analytics?.overallAccuracy ?? 0).clamp(0.0, 100.0);
    final engagement = (((_analytics?.totalAttempts ?? 0) / 20) * 100).clamp(0.0, 100.0);
    return {'Consistency': consistency, 'Accuracy': accuracy, 'Engagement': engagement};
  }

  double get _healthScore {
    final b = _healthBreakdown;
    return (b.values.reduce((a, c) => a + c) / b.length);
  }

  List<_Achievement> get _achievements {
    final longestStreak = _streak?.longestStreak ?? 0;
    final totalAttempts = _analytics?.totalAttempts ?? 0;
    final accuracy = _analytics?.overallAccuracy ?? 0;
    final highest = _analytics?.highestScore ?? 0;
    final activeThisWeek = _streak?.activeDaysThisWeek ?? 0;
    final hasCompletedCourse = _subjects.any((s) => s.progressPercentage >= 100);

    return [
      _Achievement('\u{1F525}', '7 Day Streak', longestStreak >= 7, 'Reach a 7-day streak'),
      _Achievement('\u{1F947}', 'Quiz Master', totalAttempts >= 10 && accuracy >= 80, '10+ quizzes at 80%+ accuracy'),
      _Achievement('\u{1F4DA}', 'Course Champion', hasCompletedCourse, 'Complete any full subject'),
      _Achievement('\u26A1', 'Fast Learner', _totalLessonsCompleted >= 20, 'Complete 20+ lessons'),
      _Achievement('\u{1F3C6}', 'Top Performer', highest >= 100, 'Score 100% on any quiz'),
      _Achievement('\u{1F3AF}', 'Goal Achiever', activeThisWeek >= 7, 'Active all 7 days this week'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Learning Progress'),
        elevation: 0,
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.textPrimary,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? _buildSkeleton()
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        SkeletonBox(height: 220, borderRadius: BorderRadius.all(Radius.circular(28))),
        SizedBox(height: 16),
        SkeletonBox(height: 150, borderRadius: BorderRadius.all(Radius.circular(24))),
        SizedBox(height: 16),
        SkeletonBox(height: 200, borderRadius: BorderRadius.all(Radius.circular(24))),
      ],
    );
  }

  Widget _buildError() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary))),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry'))),
      ],
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Text('Track your learning journey', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        const SizedBox(height: 20),
        _buildHeroCard(),
        const SizedBox(height: 20),
        _buildStreakCard(),
        const SizedBox(height: 20),
        _buildStudyTimeCard(),
        const SizedBox(height: 28),
        _sectionTitle('Course Progress'),
        const SizedBox(height: 10),
        ..._subjects.where((s) => s.lessonCount > 0).map(_buildCourseCard),
        const SizedBox(height: 28),
        _sectionTitle('Quiz Performance'),
        const SizedBox(height: 10),
        _buildQuizPerformanceCard(),
        const SizedBox(height: 20),
        _buildWeeklyTrendCard(),
        const SizedBox(height: 28),
        _sectionTitle('Learning Calendar'),
        const SizedBox(height: 10),
        _buildHeatmapCard(),
        const SizedBox(height: 28),
        _sectionTitle('Achievements'),
        const SizedBox(height: 10),
        _buildAchievements(),
        const SizedBox(height: 28),
        _sectionTitle('AI Insights'),
        const SizedBox(height: 10),
        _buildAiInsights(),
        const SizedBox(height: 28),
        _sectionTitle('Learning Health Score'),
        const SizedBox(height: 10),
        _buildHealthScoreCard(),
        const SizedBox(height: 28),
        _sectionTitle('Recommended Actions'),
        const SizedBox(height: 10),
        _buildRecommendedActions(),
      ],
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700));

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: [Color(0xFF7C5CFC), Color(0xFFA78BFA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: AppColors.purple.withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _overallProgress / 100),
                      duration: const Duration(milliseconds: 800),
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 7,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    Text('${_overallProgress.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text('Overall Progress', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _heroStat('Courses', '$_coursesCompleted/${_subjects.where((s) => s.lessonCount > 0).length}'),
              _heroStat('Lessons', '$_totalLessonsCompleted'),
              _heroStat('Hours', _totalCompletedHours.toStringAsFixed(1)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push(_inProgressSubjects.isNotEmpty
                  ? '/lessons'
                  : '/categories', extra: _inProgressSubjects.isNotEmpty
                  ? {'subjectId': _inProgressSubjects.first.id, 'subjectName': _inProgressSubjects.first.name}
                  : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.purple,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Continue Learning', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStreakCard() {
    final weekly = _streak?.weeklyActivity ?? List.filled(7, false);
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('\u{1F525} Learning Streak', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              Text(_streak?.currentStreak == 0 ? 'Start today!' : "You're doing great!", style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _streakStat('Current', '${_streak?.currentStreak ?? 0} Days', AppColors.purple),
              const SizedBox(width: 20),
              _streakStat('Longest', '${_streak?.longestStreak ?? 0} Days', AppColors.orange),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final active = i < weekly.length && weekly[i];
              return Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: active ? AppColors.purple : AppColors.pageBackground,
                      shape: BoxShape.circle,
                    ),
                    child: active ? const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 15) : null,
                  ),
                  const SizedBox(height: 4),
                  Text(dayLabels[i], style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _streakStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildStudyTimeCard() {
    return _whiteCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.access_time_filled_rounded, color: AppColors.orange),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Study Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text('${_totalCompletedHours.toStringAsFixed(1)} hours across completed lessons', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard(SubjectModel s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _whiteCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.purple.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.menu_book_rounded, color: AppColors.purple),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${s.completedLessons}/${s.lessonCount} lessons', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (s.progressPercentage / 100).clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: AppColors.purple.withOpacity(0.12),
                      valueColor: const AlwaysStoppedAnimation(AppColors.purple),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('${s.progressPercentage.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.purple)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizPerformanceCard() {
    final a = _analytics;
    return _whiteCard(
      child: Column(
        children: [
          Row(
            children: [
              _quizStat('${a?.totalAttempts ?? 0}', 'Attempted', AppColors.blue),
              _quizStat('${a?.passedCount ?? 0}', 'Passed', AppColors.green),
              _quizStat('${a?.failedCount ?? 0}', 'Failed', AppColors.error),
            ],
          ),
          const Divider(height: 28),
          Row(
            children: [
              _quizStat('${a?.averageScore.toStringAsFixed(0) ?? 0}%', 'Average', AppColors.purple),
              _quizStat('${a?.highestScore ?? 0}%', 'Highest', AppColors.orange),
              _quizStat('${a?.overallAccuracy.toStringAsFixed(0) ?? 0}%', 'Accuracy', AppColors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quizStat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildWeeklyTrendCard() {
    final trend = _analytics?.weeklyTrend ?? [];
    if (trend.isEmpty) return const SizedBox.shrink();

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This Week\'s Accuracy', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 16),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: trend.map((d) {
                final label = d.date.length >= 10 ? d.date.substring(8, 10) : d.date;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(d.attempts > 0 ? '${d.accuracy.toStringAsFixed(0)}' : '-', style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: d.attempts > 0 ? (d.accuracy / 100).clamp(0.05, 1) : 0.02),
                          duration: const Duration(milliseconds: 600),
                          builder: (context, value, _) => Container(
                            height: 50 * value,
                            decoration: BoxDecoration(
                              color: d.attempts > 0 ? AppColors.purple : AppColors.purpleLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapCard() {
    final month = _calendarMonth;
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;

    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday-first weekday index (0 = Monday ... 6 = Sunday).
    final leadingBlanks = (firstDayOfMonth.weekday - 1) % 7;

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _goToMonth(-1),
                tooltip: 'Previous month',
              ),
              Text(
                '${_monthNames[month.month - 1]} ${month.year}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: isCurrentMonth ? null : () => _goToMonth(1),
                tooltip: 'Next month',
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Row(
            children: [
              _WeekdayLabel('M'), _WeekdayLabel('T'), _WeekdayLabel('W'),
              _WeekdayLabel('T'), _WeekdayLabel('F'), _WeekdayLabel('S'), _WeekdayLabel('S'),
            ],
          ),
          const SizedBox(height: 6),
          if (_loadingCalendar)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4),
              itemCount: leadingBlanks + daysInMonth,
              itemBuilder: (context, index) {
                if (index < leadingBlanks) return const SizedBox.shrink();
                final day = index - leadingBlanks + 1;
                final dateKey = '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                final isActive = _calendarActiveDates.contains(dateKey);
                final isToday = isCurrentMonth && day == now.day;
                return Container(
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.purple : AppColors.pageBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: isToday ? Border.all(color: AppColors.purple, width: 1.5) : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: AppColors.purple, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              const Text('Active day', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAchievements() {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _achievements.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final a = _achievements[index];
          return Container(
            width: 110,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: a.unlocked ? AppColors.purpleLight : AppColors.card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppTheme.softShadow,
              border: a.unlocked ? null : Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(opacity: a.unlocked ? 1 : 0.35, child: Text(a.emoji, style: const TextStyle(fontSize: 26))),
                const Spacer(),
                Text(a.title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: a.unlocked ? AppColors.purple : AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (!a.unlocked) Text(a.hint, style: const TextStyle(fontSize: 8, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAiInsights() {
    final strength = _strongestSubject;
    final weakness = _weakestSubject;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('\u{1F916} AI Learning Insights', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 14),
          if (strength == null && weakness == null)
            const Text('Take a few quizzes to unlock personalized insights.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
          else ...[
            if (strength != null) _insightRow('Strength', strength.subjectName, AppColors.green),
            if (weakness != null) _insightRow('Needs Improvement', weakness.subjectName, AppColors.error),
            if (weakness != null) ...[
              const SizedBox(height: 10),
              Text('Recommendation: Practice more ${weakness.subjectName} quizzes to raise your accuracy above 60%.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _insightRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildHealthScoreCard() {
    final breakdown = _healthBreakdown;
    return _whiteCard(
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _healthScore / 100),
                  duration: const Duration(milliseconds: 800),
                  builder: (context, value, _) => CircularProgressIndicator(
                    value: value,
                    strokeWidth: 8,
                    backgroundColor: AppColors.purpleLight,
                    valueColor: const AlwaysStoppedAnimation(AppColors.purple),
                  ),
                ),
                Text('${_healthScore.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: breakdown.entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            SizedBox(width: 90, child: Text(e.key, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(value: e.value / 100, minHeight: 6, backgroundColor: AppColors.purpleLight, valueColor: const AlwaysStoppedAnimation(AppColors.purple)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('${e.value.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedActions() {
    final actions = <_ActionItem>[];
    if (_inProgressSubjects.isNotEmpty) {
      final s = _inProgressSubjects.first;
      actions.add(_ActionItem(Icons.play_circle_rounded, 'Continue ${s.name}', AppColors.purple, () => context.push('/lessons', extra: {'subjectId': s.id, 'subjectName': s.name})));
    }
    final weakness = _weakestSubject;
    if (weakness != null) {
      actions.add(_ActionItem(Icons.quiz_rounded, 'Practice ${weakness.subjectName} Quiz', AppColors.blue, () => context.push('/ai-quiz-generator')));
    }
    actions.add(_ActionItem(Icons.smart_toy_rounded, 'Ask AI Tutor a Question', AppColors.orange, () => context.push('/ai-tutor')));
    actions.add(_ActionItem(Icons.explore_rounded, 'Browse New Courses', AppColors.green, () => context.push('/categories')));

    return Column(
      children: actions
          .map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: a.onTap,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.softShadow),
                      child: Row(
                        children: [
                          Icon(a.icon, color: a.color, size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _whiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(22), boxShadow: AppTheme.softShadow),
      child: child,
    );
  }
}

class _Achievement {
  final String emoji;
  final String title;
  final bool unlocked;
  final String hint;
  _Achievement(this.emoji, this.title, this.unlocked, this.hint);
}

class _ActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _ActionItem(this.icon, this.label, this.color, this.onTap);
}

// --- Learning Calendar month view (additive) ---
class _WeekdayLabel extends StatelessWidget {
  final String label;
  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      ),
    );
  }
}
'@
[System.IO.File]::WriteAllText("$Root\frontend\lib\screens\quiz\progress_dashboard_screen.dart", $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Written: frontend\lib\screens\quiz\progress_dashboard_screen.dart"

Write-Host ""
Write-Host "All files written successfully." -ForegroundColor Green