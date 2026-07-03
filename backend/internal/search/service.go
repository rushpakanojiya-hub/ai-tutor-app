package search

import (
	"errors"

	"ai-tutor-backend/internal/categories"
	"ai-tutor-backend/internal/lessons"
	"ai-tutor-backend/internal/subjects"
)

// ErrEmptyQuery is returned when the search term is blank.
var ErrEmptyQuery = errors.New("search query cannot be empty")

// Service fans a single search query out to the three existing
// repositories' SearchByName/SearchByTitle methods, added specifically
// for this feature (see each repository.go).
type Service struct {
	categoriesRepo *categories.Repository
	subjectsRepo   *subjects.Repository
	lessonsRepo    *lessons.Repository
}

// NewService wires the three repositories into a search Service.
func NewService(categoriesRepo *categories.Repository, subjectsRepo *subjects.Repository, lessonsRepo *lessons.Repository) *Service {
	return &Service{
		categoriesRepo: categoriesRepo,
		subjectsRepo:   subjectsRepo,
		lessonsRepo:    lessonsRepo,
	}
}

// Search runs the query against categories, subjects, and lessons in
// parallel-friendly sequential calls (small dataset, no need for goroutines
// yet) and returns everything bundled together.
func (s *Service) Search(query string) (*Results, error) {
	if query == "" {
		return nil, ErrEmptyQuery
	}

	cats, err := s.categoriesRepo.SearchByName(query)
	if err != nil {
		return nil, err
	}
	subs, err := s.subjectsRepo.SearchByName(query)
	if err != nil {
		return nil, err
	}
	less, err := s.lessonsRepo.SearchByTitle(query)
	if err != nil {
		return nil, err
	}

	return &Results{
		Categories: cats,
		Subjects:   subs,
		Lessons:    less,
	}, nil
}