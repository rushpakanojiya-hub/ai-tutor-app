package badge

import "ai-tutor-backend/internal/streak"

const (
	quizMasterThreshold      = 10
	homeworkHeroThreshold    = 5
	mathChampionThreshold    = 5
	studyStreakThresholdDays = 7
)

type Service struct {
	repo       *Repository
	streakRepo *streak.Repository
}

func NewService(repo *Repository, streakRepo *streak.Repository) *Service {
	return &Service{repo: repo, streakRepo: streakRepo}
}

// ListForStudent returns all 7 badges with earned/locked status - used
// by both the student's own "My Badges" page and the teacher/admin
// view-a-student's-badges page (same data, no earning capability there).
func (s *Service) ListForStudent(studentID int) ([]BadgeStatus, error) {
	badges, err := s.repo.ListAllBadges()
	if err != nil {
		return nil, err
	}
	earned, err := s.repo.EarnedByStudent(studentID)
	if err != nil {
		return nil, err
	}

	result := make([]BadgeStatus, 0, len(badges))
	for _, b := range badges {
		status := BadgeStatus{Key: b.Key, Name: b.Name, Description: b.Description, IconKey: b.IconKey}
		if earnedAt, ok := earned[b.Key]; ok {
			status.Unlocked = true
			t := earnedAt
			status.EarnedAt = &t
		}
		result = append(result, status)
	}
	return result, nil
}

// CheckAndAwardBadges re-evaluates every achievement condition for a
// student and awards any newly-qualifying badges. Called (fire-and-
// forget, from a goroutine) after quiz attempts, assignment submissions,
// lesson completions, and live-class check-ins - it's cheap and
// idempotent (Award is a no-op for badges already earned), so re-running
// it on every relevant action is simpler and safer than trying to track
// "did this specific action cross the threshold" in each caller.
func (s *Service) CheckAndAwardBadges(studentID int) {
	if count, err := s.repo.PassedQuizCount(studentID); err == nil && count >= quizMasterThreshold {
		_ = s.repo.Award(studentID, KeyQuizMaster)
	}
	if count, err := s.repo.SubmittedAssignmentCount(studentID); err == nil && count >= homeworkHeroThreshold {
		_ = s.repo.Award(studentID, KeyHomeworkHero)
	}
	if count, err := s.repo.PassedMathQuizCount(studentID); err == nil && count >= mathChampionThreshold {
		_ = s.repo.Award(studentID, KeyMathChampion)
	}
	if hasPerfect, err := s.repo.HasPerfectScore(studentID); err == nil && hasPerfect {
		_ = s.repo.Award(studentID, KeyPerfectScore)
	}
	if finished, err := s.repo.HasFinishedAnyCourse(studentID); err == nil && finished {
		_ = s.repo.Award(studentID, KeyCourseFinisher)
	}
	if perfectAttendance, err := s.repo.HasPerfectAttendance(studentID); err == nil && perfectAttendance {
		_ = s.repo.Award(studentID, KeyAttendanceStar)
	}
	if s.streakRepo != nil {
		if current, err := s.streakRepo.GetCurrentStreak(studentID); err == nil && current >= studyStreakThresholdDays {
			_ = s.repo.Award(studentID, KeyStudyStreak7)
		}
	}
}
