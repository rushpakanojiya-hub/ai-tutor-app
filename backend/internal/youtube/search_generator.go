package youtube

import "fmt"

// GenerateSearchQuery builds an educational search query for a lesson when
// lessons.youtube_search_query is empty. This is a lightweight template-based
// generator (no AI Tutor / LLM dependency, per scope). If you later want
// smarter queries, plug an LLM call in here without touching AI Tutor code.
func GenerateSearchQuery(lessonTitle, subjectName string) string {
	if lessonTitle == "" {
		return subjectName + " educational video"
	}
	if subjectName == "" {
		return lessonTitle + " tutorial for beginners"
	}
	return fmt.Sprintf("%s %s educational video tutorial", subjectName, lessonTitle)
}

// GenerateQueryVariants returns a few alternative phrasings, useful if the
// primary query returns zero results and you want a fallback retry.
func GenerateQueryVariants(lessonTitle, subjectName string) []string {
	variants := []string{
		fmt.Sprintf("%s for beginners", lessonTitle),
		fmt.Sprintf("%s tutorial", lessonTitle),
	}
	if subjectName != "" {
		variants = append(variants, fmt.Sprintf("%s %s class", subjectName, lessonTitle))
	}
	return variants
}
