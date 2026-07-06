package search

import (
	"errors"

	"ai-tutor-backend/internal/aicontent"
	"ai-tutor-backend/internal/categories"
	"ai-tutor-backend/internal/lessons"
	"ai-tutor-backend/internal/subjects"
)

// ErrEmptyQuery is returned when the search term is blank.
var ErrEmptyQuery = errors.New("search query cannot be empty")

// Service fans a single search query out to categories, subjects, lessons,
// and (new, per this request) lesson AI content explanation/summary text â€”
// so searching "variables" finds the Algebra lesson even if "variables"
// isn't in its title.
type Service struct {
	categoriesRepo *categories.Repository
	subjectsRepo   *subjects.Repository
	lessonsRepo    *lessons.Repository
	aiContentRepo  *aicontent.Repository
}

// NewService wires the repositories into a search Service.
func NewService(
	categoriesRepo *categories.Repository,
	subjectsRepo *subjects.Repository,
	lessonsRepo *lessons.Repository,
	aiContentRepo *aicontent.Repository,
) *Service {
	return &Service{
		categoriesRepo: categoriesRepo,
		subjectsRepo:   subjectsRepo,
		lessonsRepo:    lessonsRepo,
		aiContentRepo:  aiContentRepo,
	}
}

// Search runs the query against categories, subjects, lesson titles, and
// lesson AI content, merging the lesson results (deduplicated) into one list.
func (s *Service) Search(query string) (*Results, error) {
	if query == "" {
		return nil, ErrEmptyQuery
	}

	cats, err := s.categoriesRepo.SearchByName(query)
	if err != nil {
		return nil, err
	}
	subs, err := s.subjectsRepo.SearchByName(0, query)
	if err != nil {
		return nil, err
	}
	lessonsByTitle, err := s.lessonsRepo.SearchByTitle(query)
	if err != nil {
		return nil, err
	}

	// Merge in lessons whose AI explanation/summary matches the query,
	// even if the title itself doesn't.
	matchedIDs, err := s.aiContentRepo.SearchByText(query)
	if err != nil {
		return nil, err
	}
	seen := make(map[int]bool)
	for _, l := range lessonsByTitle {
		seen[l.ID] = true
	}
	for _, id := range matchedIDs {
		if seen[id] {
			continue
		}
		lesson, err := s.lessonsRepo.FindByID(id)
		if err != nil {
			continue // skip silently â€” a stale/missing lesson shouldn't break search
		}
		lessonsByTitle = append(lessonsByTitle, *lesson)
		seen[id] = true
	}

	return &Results{
		Categories: cats,
		Subjects:   subs,
		Lessons:    lessonsByTitle,
	}, nil
}
