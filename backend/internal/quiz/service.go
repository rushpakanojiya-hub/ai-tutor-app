package quiz

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"

	"ai-tutor-backend/internal/ai"
	"ai-tutor-backend/internal/badge"
	"ai-tutor-backend/internal/streak"
	"ai-tutor-backend/internal/xp"
)

// ErrNoQuizForLesson is returned when a lesson has no AI-generated quiz yet.
var ErrNoQuizForLesson = errors.New("this lesson has no quiz yet")

// ErrAnswerCountMismatch is returned when the submitted answers array
// doesn't match the lesson's actual question count.
var ErrAnswerCountMismatch = errors.New("answers count does not match question count")

var allQuestionTypes = []string{
	QuestionTypeSingleMCQ, QuestionTypeMultipleMCQ, QuestionTypeTrueFalse,
	QuestionTypeFillBlank, QuestionTypeShortAnswer,
}

// Service contains the business logic for quiz attempts, grading,
// analytics, and AI quiz generation.
type Service struct {
	repo       *Repository
	groqClient *ai.GroqClient
	streakSvc  *streak.Service
	badgeSvc   *badge.Service
	xpSvc      *xp.Service
}

// NewService wires a Repository, the shared GroqClient, the shared
// streak Service, and the shared badge Service into a quiz Service.
func NewService(repo *Repository, groqClient *ai.GroqClient, streakSvc *streak.Service, badgeSvc *badge.Service, xpSvc *xp.Service) *Service {
	return &Service{repo: repo, groqClient: groqClient, streakSvc: streakSvc, badgeSvc: badgeSvc, xpSvc: xpSvc}
}

// SubmitLessonAttempt grades a lesson-based quiz attempt server-side
// (using the lesson's stored quiz_json as the answer key) and persists
// it. Lesson quizzes are always single_mcq, unchanged from before.
func (s *Service) SubmitLessonAttempt(userID, lessonID int, req SubmitLessonAttemptRequest) (*AttemptWithAnswers, error) {
	questions, err := s.repo.GetLessonQuiz(lessonID)
	if err != nil {
		return nil, err
	}
	if len(questions) == 0 {
		return nil, ErrNoQuizForLesson
	}
	if len(req.Answers) != len(questions) {
		return nil, ErrAnswerCountMismatch
	}

	subjectID, err := s.repo.GetLessonSubjectID(lessonID)
	if err != nil {
		return nil, err
	}

	answers := make([]AttemptAnswer, len(questions))
	for i, q := range questions {
		selected := req.Answers[i]
		var selectedPtr *int
		if selected >= 0 {
			selectedPtr = &selected
		}
		correctOption := q.CorrectOption
		answers[i] = AttemptAnswer{
			QuestionIndex:  i,
			QuestionType:   QuestionTypeSingleMCQ,
			QuestionText:   q.Question,
			Options:        q.Options,
			SelectedOption: selectedPtr,
			CorrectOption:  &correctOption,
			IsCorrect:      selectedPtr != nil && *selectedPtr == q.CorrectOption,
		}
	}

	lid := lessonID
	sid := subjectID
	attemptID, err := s.repo.SaveAttempt(userID, &lid, &sid, "", req.TimeTakenSeconds, answers)
	if err != nil {
		return nil, err
	}
	_ = s.streakSvc.RecordActivity(userID) // best-effort
	go s.badgeSvc.CheckAndAwardBadges(userID)
	go s.xpSvc.AwardQuizCompletion(userID, attemptID)
	go s.xpSvc.OnStudyActivity(userID)

	return s.repo.GetAttemptWithAnswers(userID, attemptID)
}

// SubmitFreeformAttempt grades and persists an AI-generated quiz that
// isn't tied to a specific lesson. Grading logic depends on each
// question's type (there's no server-stored answer key for these - the
// client already has it from /generate).
func (s *Service) SubmitFreeformAttempt(userID int, req SubmitFreeformAttemptRequest) (*AttemptWithAnswers, error) {
	if len(req.Questions) == 0 {
		return nil, errors.New("at least one question is required")
	}

	answers := make([]AttemptAnswer, len(req.Questions))
	for i, q := range req.Questions {
		qType := q.QuestionType
		if qType == "" {
			qType = QuestionTypeSingleMCQ
		}

		answer := AttemptAnswer{
			QuestionIndex:   i,
			QuestionType:    qType,
			QuestionText:    q.Question,
			Options:         q.Options,
			CorrectOption:   q.CorrectOption,
			CorrectOptions:  q.CorrectOptions,
			CorrectText:     q.CorrectText,
			Hint:            q.Hint,
			Explanation:     q.Explanation,
			DifficultyScore: q.DifficultyScore,
			SelectedOption:  q.SelectedOption,
			SelectedOptions: q.SelectedOptions,
			SubmittedText:   q.SubmittedText,
		}

		switch qType {
		case QuestionTypeMultipleMCQ:
			answer.IsCorrect = intSetsEqual(q.SelectedOptions, q.CorrectOptions)
		case QuestionTypeFillBlank, QuestionTypeShortAnswer:
			answer.IsCorrect = normalizeAnswerText(q.SubmittedText) == normalizeAnswerText(q.CorrectText) && q.CorrectText != ""
		default: // single_mcq, true_false
			answer.IsCorrect = q.SelectedOption != nil && q.CorrectOption != nil && *q.SelectedOption == *q.CorrectOption
		}

		answers[i] = answer
	}

	attemptID, err := s.repo.SaveAttempt(userID, nil, req.SubjectID, req.Topic, req.TimeTakenSeconds, answers)
	if err != nil {
		return nil, err
	}
	_ = s.streakSvc.RecordActivity(userID) // best-effort
	go s.badgeSvc.CheckAndAwardBadges(userID)
	go s.xpSvc.AwardQuizCompletion(userID, attemptID)
	go s.xpSvc.OnStudyActivity(userID)
	return s.repo.GetAttemptWithAnswers(userID, attemptID)
}

func intSetsEqual(a, b []int) bool {
	if len(a) != len(b) || len(a) == 0 {
		return false
	}
	ac := append([]int{}, a...)
	bc := append([]int{}, b...)
	sort.Ints(ac)
	sort.Ints(bc)
	for i := range ac {
		if ac[i] != bc[i] {
			return false
		}
	}
	return true
}

func normalizeAnswerText(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

// ListAttempts returns a user's quiz history.
func (s *Service) ListAttempts(userID, lessonID int) ([]Attempt, error) {
	return s.repo.ListAttempts(userID, lessonID)
}

// GetAttempt returns one attempt with its full per-question breakdown.
func (s *Service) GetAttempt(userID, attemptID int) (*AttemptWithAnswers, error) {
	return s.repo.GetAttemptWithAnswers(userID, attemptID)
}

// GetAnalytics returns accuracy analytics computed from real attempt data.
func (s *Service) GetAnalytics(userID int) (*Analytics, error) {
	return s.repo.GetAnalytics(userID)
}

// GenerateQuiz asks Groq for a fresh set of quiz questions on a topic,
// mixing in whichever question types were requested (defaulting to
// single_mcq only, so existing callers are unaffected).
func (s *Service) GenerateQuiz(ctx context.Context, req GenerateQuizRequest) ([]FreeformQuestion, error) {
	numQuestions := req.NumQuestions
	if numQuestions <= 0 {
		numQuestions = 5
	}
	if numQuestions > 10 {
		numQuestions = 10
	}
	difficulty := req.Difficulty
	if difficulty == "" {
		difficulty = "medium"
	}

	questionTypes := sanitizeQuestionTypes(req.QuestionTypes)

	assignments := make([]string, numQuestions)
	for i := 0; i < numQuestions; i++ {
		assignments[i] = questionTypes[i%len(questionTypes)]
	}
	var assignmentLines strings.Builder
	for i, t := range assignments {
		assignmentLines.WriteString(fmt.Sprintf("Question %d MUST have \"question_type\": \"%s\"\n", i+1, t))
	}

	systemPrompt := "You are an expert exam-prep quiz writer. You output ONLY raw JSON - no markdown code fences, no preamble. You follow the exact question_type assigned to each question - you never substitute a different type."
	userPrompt := fmt.Sprintf(`Generate exactly %d quiz questions about "%s" at %s difficulty.

Question type assignment (follow exactly, in this order):
%s
Return ONLY a JSON array of %d elements, in the same order as the assignment above. Each element's shape depends on its "question_type":

- "single_mcq" or "true_false": {"question_type": "...", "question": "...", "options": ["...", "...", "...", "..."], "correct_option": 0, "hint": "...", "explanation": "...", "difficulty_score": 5}
  (true_false must have exactly 2 options: "True" and "False")
- "multiple_mcq": {"question_type": "multiple_mcq", "question": "...", "options": ["...", "...", "...", "..."], "correct_options": [0, 2], "hint": "...", "explanation": "...", "difficulty_score": 5}
  (multiple_mcq must have at least 2 correct_options - if you can only think of 1 correct answer, pick a different question)
- "fill_blank" or "short_answer": {"question_type": "...", "question": "... (use ____ for the blank if fill_blank)", "correct_text": "the expected answer", "hint": "...", "explanation": "...", "difficulty_score": 5}
  (do NOT include an "options" field for these two types)

Rules:
- The "question_type" in your output for question N must exactly match the assignment above for question N - do not default to single_mcq.
- correct_option / correct_options are 0-based indices into "options".
- difficulty_score is 1-10 (1=very easy, 10=very hard), consistent with "%s" difficulty.
- hint must not give away the answer directly.
- Output nothing but the JSON array of exactly %d elements.`, numQuestions, req.Topic, difficulty, assignmentLines.String(), numQuestions, difficulty, numQuestions)

	messages := []ai.ChatCompletionMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	raw, err := s.groqClient.Chat(ctx, messages)
	if err != nil {
		return nil, err
	}

	clean := strings.TrimSpace(raw)
	clean = strings.TrimPrefix(clean, "```json")
	clean = strings.TrimPrefix(clean, "```")
	clean = strings.TrimSuffix(clean, "```")
	clean = strings.TrimSpace(clean)

	var questions []FreeformQuestion
	if err := json.Unmarshal([]byte(clean), &questions); err != nil {
		return nil, fmt.Errorf("invalid JSON from Groq: %w", err)
	}

	for i := range questions {
		if i < len(assignments) {
			questions[i].QuestionType = assignments[i]
		} else if questions[i].QuestionType == "" {
			questions[i].QuestionType = QuestionTypeSingleMCQ
		}
		if questions[i].DifficultyScore == 0 {
			questions[i].DifficultyScore = 5
		}
	}

	return questions, nil
}

func sanitizeQuestionTypes(requested []string) []string {
	if len(requested) == 0 {
		return []string{QuestionTypeSingleMCQ}
	}
	valid := map[string]bool{}
	for _, t := range allQuestionTypes {
		valid[t] = true
	}
	var result []string
	for _, t := range requested {
		if valid[t] {
			result = append(result, t)
		}
	}
	if len(result) == 0 {
		return []string{QuestionTypeSingleMCQ}
	}
	return result
}
