# apply_gamification_fixes.ps1
# Run from your backend project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\backend)
# Writes: streak module (Asia/Kolkata timezone fix), badge/progress modules
# (rows.Err fixes), xp module (matching timezone fix for daily XP dedup).
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$root = Get-Location
Write-Host "Applying gamification fixes in $root" -ForegroundColor Cyan

# --- internal/streak/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/streak") | Out-Null
$content_internal_streak_repository_go = @'
// Package streak computes a real "Learning Streak" from actual student
// activity (lesson completions, quiz attempts, AI Tutor chats) - no
// fabricated numbers. Any of those three actions marks "today" as active
// for that user.
package streak

import (
	"database/sql"
	"log"
	"time"
)

// BUG FIX (timezone mismatch - audit-flagged, highest-risk file):
// every "today"/"this week"/"last N days" calculation here used to mix
// two different, independently-configured clocks: Go's time.Now()
// (whatever timezone the app process's container happens to be running
// in - typically UTC by default) on one side, and Postgres's CURRENT_DATE
// (whatever timezone the DB session happens to be configured with) on
// the other. If those two didn't agree - or either one didn't match this
// app's actual (India-based) users - "today" could disagree by hours,
// breaking streak continuity right around midnight and giving a wrong
// current/longest streak or a weekly activity graph shifted by a day.
// istLocation makes the timezone explicit and identical on both the Go
// side (todayIST) and the SQL side (the "AT TIME ZONE 'Asia/Kolkata'"
// queries below), so the two can never silently disagree again. If your
// users are in a different timezone, change both consistently.
var istLocation = mustLoadIST()

func mustLoadIST() *time.Location {
	loc, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("[streak] failed to load Asia/Kolkata timezone, falling back to UTC: %v", err)
		return time.UTC
	}
	return loc
}

// todayIST returns today's date (midnight) in the app's canonical
// timezone, replacing the previous ambient time.Now() calls.
func todayIST() time.Time {
	return truncateToDate(time.Now().In(istLocation))
}

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// RecordActivity marks today (in IST) as an active day for userID.
// Idempotent - safe to call many times in the same day.
func (r *Repository) RecordActivity(userID int) error {
	_, err := r.db.Exec(`
		INSERT INTO user_activity_days (user_id, activity_date)
		VALUES ($1, (now() AT TIME ZONE 'Asia/Kolkata')::date)
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

	today := todayIST()
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
// been active since the start of the current calendar week (IST).
func (r *Repository) GetActiveDaysThisWeek(userID int) (int, error) {
	var count int
	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= date_trunc('week', (now() AT TIME ZONE 'Asia/Kolkata')::date)`, userID,
	).Scan(&count)
	return count, err
}

// GetWeeklyActivity returns a 7-element bool array for the last 7 days
// (oldest first, today last), true if the user was active that day - for
// the "weekly streak graph".
func (r *Repository) GetWeeklyActivity(userID int) ([]bool, error) {
	rows, err := r.db.Query(`
		SELECT activity_date FROM user_activity_days
		WHERE user_id = $1 AND activity_date >= (now() AT TIME ZONE 'Asia/Kolkata')::date - INTERVAL '6 days'`, userID)
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
	if err := rows.Err(); err != nil {
		return nil, err
	}

	result := make([]bool, 7)
	today := todayIST()
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
		WHERE user_id = $1 AND activity_date >= (now() AT TIME ZONE 'Asia/Kolkata')::date - ($2 || ' days')::interval`, userID, days-1)
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
	if err := rows.Err(); err != nil {
		return nil, err
	}

	today := todayIST()
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

	today := todayIST()
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
[System.IO.File]::WriteAllText((Join-Path $root "internal/streak/repository.go"), $content_internal_streak_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/streak/repository.go" -ForegroundColor Green

# --- internal/streak/handler.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/streak") | Out-Null
$content_internal_streak_handler_go = @'
package streak

import (
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
// Defaults to the current year/month (in IST, matching the rest of this
// package - see repository.go's todayIST) if not provided.
func (h *Handler) GetMonthCalendar(c *gin.Context) {
	userID := c.GetInt("user_id")
	now := todayIST()

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
[System.IO.File]::WriteAllText((Join-Path $root "internal/streak/handler.go"), $content_internal_streak_handler_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/streak/handler.go" -ForegroundColor Green

# --- internal/badge/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/badge") | Out-Null
$content_internal_badge_repository_go = @'
package badge

import (
	"database/sql"
	"time"
)

// Passing threshold reused from quiz analytics ("weak topics"/pass-fail
// split already uses 60% elsewhere in the app).
const passingScore = 60

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// ListAllBadges returns the 7 fixed badge definitions.
//
// BUG FIX: was missing a rows.Err() check after the scan loop.
func (r *Repository) ListAllBadges() ([]Badge, error) {
	rows, err := r.db.Query(`SELECT id, key, name, description, icon_key FROM badges ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Badge
	for rows.Next() {
		var b Badge
		if err := rows.Scan(&b.ID, &b.Key, &b.Name, &b.Description, &b.IconKey); err != nil {
			return nil, err
		}
		result = append(result, b)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// EarnedByStudent returns key -> earned_at for every badge the student
// already has.
//
// BUG FIX: was missing a rows.Err() check after the scan loop.
func (r *Repository) EarnedByStudent(studentID int) (map[string]time.Time, error) {
	rows, err := r.db.Query(`
		SELECT b.key, sb.earned_at
		FROM student_badges sb
		JOIN badges b ON b.id = sb.badge_id
		WHERE sb.student_id = $1`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[string]time.Time)
	for rows.Next() {
		var key string
		var earnedAt time.Time
		if err := rows.Scan(&key, &earnedAt); err != nil {
			return nil, err
		}
		result[key] = earnedAt
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// Award inserts a new student_badges row for the given badge key - a
// no-op (via ON CONFLICT) if the student already has it.
func (r *Repository) Award(studentID int, badgeKey string) error {
	_, err := r.db.Exec(`
		INSERT INTO student_badges (student_id, badge_id, earned_at)
		SELECT $1, id, now() FROM badges WHERE key = $2
		ON CONFLICT (student_id, badge_id) DO NOTHING`, studentID, badgeKey)
	return err
}

// --- Individual achievement checks - each queries real existing data,
// no new tracking tables needed beyond student_badges/badges above. ---

func (r *Repository) PassedQuizCount(studentID int) (int, error) {
	var count int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM quiz_attempts WHERE user_id = $1 AND score_percent >= $2`, studentID, passingScore).Scan(&count)
	return count, err
}

func (r *Repository) PassedMathQuizCount(studentID int) (int, error) {
	var count int
	err := r.db.QueryRow(`
		SELECT COUNT(*) FROM quiz_attempts qa
		JOIN subjects s ON s.id = qa.subject_id
		WHERE qa.user_id = $1 AND qa.score_percent >= $2 AND s.name ILIKE '%math%'`, studentID, passingScore).Scan(&count)
	return count, err
}

func (r *Repository) HasPerfectScore(studentID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM quiz_attempts WHERE user_id = $1 AND score_percent = 100)`, studentID).Scan(&exists)
	return exists, err
}

func (r *Repository) SubmittedAssignmentCount(studentID int) (int, error) {
	var count int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM assignment_submissions WHERE student_id = $1 AND status != 'draft'`, studentID).Scan(&count)
	return count, err
}

// HasFinishedAnyCourse checks if the student has completed every lesson
// in at least one subject that has at least one lesson.
func (r *Repository) HasFinishedAnyCourse(studentID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`
		SELECT EXISTS(
			SELECT 1 FROM subjects s
			WHERE (SELECT COUNT(*) FROM lessons l WHERE l.subject_id = s.id) > 0
			AND (SELECT COUNT(*) FROM lessons l WHERE l.subject_id = s.id) = (
				SELECT COUNT(*) FROM lesson_progress lp
				JOIN lessons l2 ON l2.id = lp.lesson_id
				WHERE l2.subject_id = s.id AND lp.user_id = $1
			)
		)`, studentID).Scan(&exists)
	return exists, err
}

// HasPerfectAttendance checks if the student attended every completed
// live class in at least one subject with 3+ completed classes.
func (r *Repository) HasPerfectAttendance(studentID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`
		SELECT EXISTS(
			SELECT 1 FROM live_classes lc
			WHERE lc.subject_id IS NOT NULL
			AND (SELECT COUNT(*) FROM live_classes lc2 WHERE lc2.subject_id = lc.subject_id AND lc2.status = 'completed') >= 3
			AND (SELECT COUNT(*) FROM live_classes lc3 WHERE lc3.subject_id = lc.subject_id AND lc3.status = 'completed') = (
				SELECT COUNT(*) FROM live_class_attendance a
				JOIN live_classes lc4 ON lc4.id = a.live_class_id
				WHERE lc4.subject_id = lc.subject_id AND lc4.status = 'completed' AND a.student_id = $1
			)
		)`, studentID).Scan(&exists)
	return exists, err
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/badge/repository.go"), $content_internal_badge_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/badge/repository.go" -ForegroundColor Green

# --- internal/xp/service.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/xp") | Out-Null
$content_internal_xp_service_go = @'
package xp

import (
	"fmt"
	"log"
	"time"

	"ai-tutor-backend/internal/streak"
)

// BUG FIX (timezone mismatch, matching the same class of bug fixed in
// streak/repository.go): AwardDailyStudy used to key its dedup date off
// time.Now() in the app process's ambient/container timezone. Since
// streak's "today" is now explicitly Asia/Kolkata, using a different
// zone here could mis-date the daily XP grant relative to the student's
// actual day, or grant/deny it inconsistently with the streak that
// triggered it. Kept consistent with streak's canonical timezone.
var istLocation = mustLoadIST()

func mustLoadIST() *time.Location {
	loc, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		log.Printf("[xp] failed to load Asia/Kolkata timezone, falling back to UTC: %v", err)
		return time.UTC
	}
	return loc
}

type Service struct {
	repo       *Repository
	streakRepo *streak.Repository
}

func NewService(repo *Repository, streakRepo *streak.Repository) *Service {
	return &Service{repo: repo, streakRepo: streakRepo}
}

// GetSummary returns the student's XP/points/level for the dashboard
// progress bar.
func (s *Service) GetSummary(studentID int) (Summary, error) {
	xpTotal, pointsTotal, err := s.repo.GetTotals(studentID)
	if err != nil {
		return Summary{}, err
	}
	return summaryFromTotals(xpTotal, pointsTotal), nil
}

// AwardQuizCompletion - called once per quiz attempt (each attempt is
// its own legitimate event, no dedup needed beyond the attempt ID itself).
func (s *Service) AwardQuizCompletion(studentID, attemptID int) {
	_ = s.repo.AwardXP(studentID, ActivityQuizCompletion, fmt.Sprintf("quiz-attempt-%d", attemptID), XPQuizCompletion, PointsQuizCompletion)
}

// AwardHomeworkSubmission - called once per assignment submission.
func (s *Service) AwardHomeworkSubmission(studentID, submissionID int) {
	_ = s.repo.AwardXP(studentID, ActivityHomeworkSubmit, fmt.Sprintf("assignment-submission-%d", submissionID), XPHomeworkSubmit, PointsHomeworkSubmit)
}

// CheckAndAwardCourseCompletion - call after any lesson completion,
// passing the subject that lesson belongs to. Only actually awards once
// per subject (the UNIQUE constraint in AwardXP handles re-checks safely).
func (s *Service) CheckAndAwardCourseCompletion(studentID, subjectID int) {
	completed, err := s.repo.IsSubjectFullyCompleted(studentID, subjectID)
	if err != nil || !completed {
		return
	}
	_ = s.repo.AwardXP(studentID, ActivityCourseCompletion, fmt.Sprintf("course-%d", subjectID), XPCourseCompletion, PointsCourseCompletion)
}

// AwardDailyStudy - call on any qualifying activity (quiz/assignment/
// lesson). Deduped by calendar date, so a student doing several
// activities the same day only gets this once.
func (s *Service) AwardDailyStudy(studentID int) {
	today := time.Now().In(istLocation).Format("2006-01-02")
	_ = s.repo.AwardXP(studentID, ActivityDailyStudy, fmt.Sprintf("daily-%s", today), XPDailyStudy, PointsDailyStudy)
}

// checkAndAwardStudyStreak awards a bonus once per completed 7-day
// block (7, 14, 21...) WITHIN the current unbroken streak run.
//
// QA fix ("Fix study streak reward logic"): the dedup key used to be
// just "streak-milestone-N", with no reference to WHICH streak run
// reached that milestone. Since the key never changes for a given N,
// a student who broke their streak and later built a brand new 7-day
// run again could never be rewarded for milestone 1 a second time -
// the UNIQUE constraint in AwardXP silently no-opped it forever after
// the very first time. Including the run's start date makes each
// distinct streak run's key unique, so genuinely new achievements are
// rewarded every time, while still never double-paying the same run.
func (s *Service) checkAndAwardStudyStreak(studentID, currentStreakDays int, streakStartDate time.Time) {
	milestone := currentStreakDays / 7
	if milestone < 1 {
		return
	}
	key := fmt.Sprintf("streak-milestone-%d-start-%s", milestone, streakStartDate.Format("2006-01-02"))
	_ = s.repo.AwardXP(studentID, ActivityStudyStreak, key, XPStudyStreak, PointsStudyStreak)
}

// OnStudyActivity is the single hook called from quiz/assignment/
// progress services after they already call streakSvc.RecordActivity -
// it awards Daily Study, then checks the (now-updated) streak length
// for a weekly milestone bonus.
func (s *Service) OnStudyActivity(studentID int) {
	s.AwardDailyStudy(studentID)
	if s.streakRepo != nil {
		if current, startDate, err := s.streakRepo.GetCurrentStreakWithStartDate(studentID); err == nil {
			s.checkAndAwardStudyStreak(studentID, current, startDate)
		}
	}
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/xp/service.go"), $content_internal_xp_service_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/xp/service.go" -ForegroundColor Green

# --- internal/progress/repository.go ---
New-Item -ItemType Directory -Force -Path (Join-Path $root "internal/progress") | Out-Null
$content_internal_progress_repository_go = @'
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

// MarkComplete records that userID has completed lessonID, optionally with
// a quiz score (0-100). Calling this again for the same (user, lesson)
// pair refreshes completed_at/score instead of erroring - re-watching a
// lesson or retaking its quiz keeps the latest result.
func (r *Repository) MarkComplete(userID, lessonID int, score *int) error {
	query := `
		INSERT INTO lesson_progress (user_id, lesson_id, completed_at, score)
		VALUES ($1, $2, NOW(), $3)
		ON CONFLICT (user_id, lesson_id)
		DO UPDATE SET completed_at = NOW(), score = COALESCE($3, lesson_progress.score)
	`
	_, err := r.db.Exec(query, userID, lessonID, score)
	return err
}

// GetLessonSubjectID resolves a lesson's subject_id - used to auto-enroll
// a student in that subject when they complete the lesson.
func (r *Repository) GetLessonSubjectID(lessonID int) (int, error) {
	var subjectID int
	err := r.db.QueryRow(`SELECT subject_id FROM lessons WHERE id = $1`, lessonID).Scan(&subjectID)
	return subjectID, err
}

// GetSubjectProgress returns the total lesson count for a subject, the
// count and IDs of lessons userID has completed within it.
func (r *Repository) GetSubjectProgress(userID, subjectID int) (*SubjectProgress, error) {
	sp := &SubjectProgress{SubjectID: subjectID}

	err := r.db.QueryRow(`SELECT COUNT(*) FROM lessons WHERE subject_id = $1`, subjectID).Scan(&sp.TotalLessons)
	if err != nil {
		return nil, err
	}

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
	// BUG FIX: was missing a rows.Err() check - a connection error mid-
	// iteration would silently under-report completed lessons instead of
	// surfacing as an error.
	if err := rows.Err(); err != nil {
		return nil, err
	}
	sp.CompletedLessons = len(sp.CompletedLessonIDs)

	if sp.TotalLessons > 0 {
		sp.Percentage = float64(sp.CompletedLessons) / float64(sp.TotalLessons)
	}

	return sp, nil
}

'@
[System.IO.File]::WriteAllText((Join-Path $root "internal/progress/repository.go"), $content_internal_progress_repository_go, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote internal/progress/repository.go" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Yellow
Write-Host "  1. go build ./... to sanity check"
Write-Host "  2. cd .. ; docker compose build --no-cache backend"
Write-Host "  3. docker compose up -d --force-recreate backend"
Write-Host "  4. docker logs ai_tutor_backend --tail 15"