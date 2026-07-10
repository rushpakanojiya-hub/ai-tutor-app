package xp

import (
	"fmt"
	"time"

	"ai-tutor-backend/internal/streak"
)

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
	today := time.Now().Format("2006-01-02")
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
