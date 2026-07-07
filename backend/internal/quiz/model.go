// Package quiz persists quiz attempts (both lesson-based and freeform
// AI-generated), grades them server-side, and computes analytics from
// real attempt data.
//
// Question types: lesson-based quizzes (from lesson_ai_content) always
// use "single_mcq" - unchanged from before. The freeform AI Quiz
// Generator additionally supports "multiple_mcq", "true_false",
// "fill_blank", and "short_answer". Match-the-following, assertion-
// reason, image-based, and numerical-answer questions are intentionally
// out of scope for now - they need substantially different UI.
package quiz

import "time"

// Supported question types for the freeform AI Quiz Generator.
const (
	QuestionTypeSingleMCQ   = "single_mcq"
	QuestionTypeMultipleMCQ = "multiple_mcq"
	QuestionTypeTrueFalse   = "true_false"
	QuestionTypeFillBlank   = "fill_blank"
	QuestionTypeShortAnswer = "short_answer"
)

// Attempt mirrors a "quiz_attempts" table row.
type Attempt struct {
	ID               int       `json:"id"`
	UserID           int       `json:"user_id"`
	LessonID         *int      `json:"lesson_id"`
	SubjectID        *int      `json:"subject_id"`
	Topic            string    `json:"topic"`
	TotalQuestions   int       `json:"total_questions"`
	CorrectCount     int       `json:"correct_count"`
	ScorePercent     int       `json:"score_percent"`
	TimeTakenSeconds *int      `json:"time_taken_seconds"`
	CreatedAt        time.Time `json:"created_at"`
}

// AttemptAnswer mirrors a "quiz_attempt_answers" table row, generalized
// to cover every supported question type. Only the fields relevant to a
// given QuestionType are populated.
type AttemptAnswer struct {
	ID              int      `json:"id"`
	AttemptID       int      `json:"attempt_id"`
	QuestionIndex   int      `json:"question_index"`
	QuestionType    string   `json:"question_type"`
	QuestionText    string   `json:"question_text"`
	Options         []string `json:"options,omitempty"`
	SelectedOption  *int     `json:"selected_option,omitempty"`
	CorrectOption   *int     `json:"correct_option,omitempty"`
	SelectedOptions []int    `json:"selected_options,omitempty"`
	CorrectOptions  []int    `json:"correct_options,omitempty"`
	SubmittedText   string   `json:"submitted_text,omitempty"`
	CorrectText     string   `json:"correct_text,omitempty"`
	Hint            string   `json:"hint,omitempty"`
	Explanation     string   `json:"explanation,omitempty"`
	DifficultyScore int      `json:"difficulty_score,omitempty"`
	IsCorrect       bool     `json:"is_correct"`
}

// AttemptWithAnswers is returned after submitting an attempt, and by the
// results/review screen.
type AttemptWithAnswers struct {
	Attempt
	Answers []AttemptAnswer `json:"answers"`
}

// SubmitLessonAttemptRequest is the body for POST /api/quiz/lessons/:id/attempt.
// Unchanged: lesson quizzes are always single_mcq, graded against the
// lesson's stored quiz_json.
type SubmitLessonAttemptRequest struct {
	Answers          []int `json:"answers" binding:"required"`
	TimeTakenSeconds int   `json:"time_taken_seconds"`
}

// FreeformQuestion is one AI-generated question returned by /generate.
// Which fields are populated depends on QuestionType.
type FreeformQuestion struct {
	QuestionType    string   `json:"question_type"`
	Question        string   `json:"question"`
	Options         []string `json:"options,omitempty"`
	CorrectOption   *int     `json:"correct_option,omitempty"`
	CorrectOptions  []int    `json:"correct_options,omitempty"`
	CorrectText     string   `json:"correct_text,omitempty"`
	Hint            string   `json:"hint,omitempty"`
	Explanation     string   `json:"explanation,omitempty"`
	DifficultyScore int      `json:"difficulty_score,omitempty"`
}

// FreeformAnswered is one question + the student's answer, sent back to
// /freeform/attempt for scoring and storage. The client already has the
// full answer key from /generate (there's no server-stored quiz bank for
// freeform quizzes), so it echoes the question data back alongside the answer.
type FreeformAnswered struct {
	QuestionType    string   `json:"question_type"`
	Question        string   `json:"question"`
	Options         []string `json:"options,omitempty"`
	CorrectOption   *int     `json:"correct_option,omitempty"`
	CorrectOptions  []int    `json:"correct_options,omitempty"`
	CorrectText     string   `json:"correct_text,omitempty"`
	Hint            string   `json:"hint,omitempty"`
	Explanation     string   `json:"explanation,omitempty"`
	DifficultyScore int      `json:"difficulty_score,omitempty"`
	SelectedOption  *int     `json:"selected_option,omitempty"`
	SelectedOptions []int    `json:"selected_options,omitempty"`
	SubmittedText   string   `json:"submitted_text,omitempty"`
}

// SubmitFreeformAttemptRequest is the body for POST /api/quiz/freeform/attempt.
type SubmitFreeformAttemptRequest struct {
	SubjectID        *int               `json:"subject_id"`
	Topic            string             `json:"topic" binding:"required"`
	TimeTakenSeconds int                `json:"time_taken_seconds"`
	Questions        []FreeformAnswered `json:"questions" binding:"required"`
}

// GenerateQuizRequest is the body for POST /api/quiz/generate.
// QuestionTypes selects which types to mix into the generated quiz -
// defaults to ["single_mcq"] if empty, so existing callers keep working
// unchanged.
type GenerateQuizRequest struct {
	SubjectID     *int     `json:"subject_id"`
	Topic         string   `json:"topic" binding:"required"`
	NumQuestions  int      `json:"num_questions"`
	Difficulty    string   `json:"difficulty"`     // "easy" | "medium" | "hard"
	QuestionTypes []string `json:"question_types"` // subset of the QuestionType* constants
}

// SubjectAccuracy is one row in the analytics response's per-subject breakdown.
type SubjectAccuracy struct {
	SubjectID   int     `json:"subject_id"`
	SubjectName string  `json:"subject_name"`
	Attempts    int     `json:"attempts"`
	Accuracy    float64 `json:"accuracy"` // 0-100
}

// DayAccuracy is one point in the weekly performance trend.
type DayAccuracy struct {
	Date     string  `json:"date"`
	Accuracy float64 `json:"accuracy"`
	Attempts int     `json:"attempts"`
}

// Analytics is the response for GET /api/quiz/analytics - all computed
// from the current user's real quiz_attempts rows. PassedCount/FailedCount
// use a 60% score threshold (same threshold used for "weak topics").
type Analytics struct {
	TotalAttempts   int               `json:"total_attempts"`
	OverallAccuracy float64           `json:"overall_accuracy"`
	PassedCount     int               `json:"passed_count"`
	FailedCount     int               `json:"failed_count"`
	AverageScore    float64           `json:"average_score"`
	HighestScore    int               `json:"highest_score"`
	BySubject       []SubjectAccuracy `json:"by_subject"`
	WeakTopics      []SubjectAccuracy `json:"weak_topics"`
	WeeklyTrend     []DayAccuracy     `json:"weekly_trend"`
}
