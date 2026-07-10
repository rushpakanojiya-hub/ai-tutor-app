package leaderboard

import (
	"errors"
	"time"

	"ai-tutor-backend/internal/users"
)

var ErrInvalidPeriod = errors.New("period must be weekly, monthly, or overall")

type Service struct {
	repo      *Repository
	usersRepo *users.Repository
}

func NewService(repo *Repository, usersRepo *users.Repository) *Service {
	return &Service{repo: repo, usersRepo: usersRepo}
}

// GetLeaderboard is role-aware: a student can only ever see their OWN
// class's leaderboard (any class/section they pass in the request is
// ignored and overridden with their own) - teachers and admins can pass
// any class/section, or none at all for the full platform-wide view.
//
// QA fix ("Prevent students without class/section from seeing the
// global leaderboard"): a student who hasn't been assigned a class/
// section yet (both empty strings) used to have those empty strings
// passed straight through as classFilter/sectionFilter - depending on
// how the repository's query built its WHERE clause, an empty-but-non-
// nil filter could be treated as "no filter", silently handing that
// student the full, unfiltered platform-wide leaderboard instead of a
// class-scoped one. Now explicitly checked: an unassigned student gets
// an empty leaderboard back, never the global one.
func (s *Service) GetLeaderboard(period string, classFilter, sectionFilter *string, requestingUserID int, requestingRole string) ([]Entry, error) {
	if requestingRole == "student" {
		ownClass, ownSection, err := s.usersRepo.GetClassSection(requestingUserID)
		if err != nil {
			return nil, err
		}
		if ownClass == "" && ownSection == "" {
			return []Entry{}, nil
		}
		classFilter = &ownClass
		sectionFilter = &ownSection
	}

	var entries []Entry
	var err error

	switch period {
	case PeriodWeekly:
		entries, err = s.repo.GetTimeScoped(time.Now().AddDate(0, 0, -7), classFilter, sectionFilter)
	case PeriodMonthly:
		entries, err = s.repo.GetTimeScoped(time.Now().AddDate(0, -1, 0), classFilter, sectionFilter)
	case PeriodOverall, "":
		entries, err = s.repo.GetOverall(classFilter, sectionFilter)
	default:
		return nil, ErrInvalidPeriod
	}
	if err != nil {
		return nil, err
	}

	for i := range entries {
		if entries[i].StudentID == requestingUserID {
			entries[i].IsCurrentUser = true
		}
	}
	return entries, nil
}
