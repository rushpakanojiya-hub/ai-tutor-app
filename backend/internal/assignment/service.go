package assignment

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"ai-tutor-backend/internal/ai"
	"ai-tutor-backend/internal/streak"
	"ai-tutor-backend/internal/subjects"
)

type Service struct {
	repo         *Repository
	subjectsRepo *subjects.Repository
	groqClient   *ai.GroqClient
	streakSvc    *streak.Service
}

func NewService(repo *Repository, subjectsRepo *subjects.Repository, groqClient *ai.GroqClient, streakSvc *streak.Service) *Service {
	return &Service{repo: repo, subjectsRepo: subjectsRepo, groqClient: groqClient, streakSvc: streakSvc}
}

// --- Teacher: CRUD ---

func (s *Service) CreateAssignment(teacherID int, req CreateAssignmentRequest) (int, error) {
	return s.repo.CreateAssignment(teacherID, req)
}

func (s *Service) UpdateAssignment(assignmentID, teacherID int, req UpdateAssignmentRequest) error {
	return s.repo.UpdateAssignment(assignmentID, teacherID, req)
}

func (s *Service) DeleteAssignment(assignmentID, teacherID int) error {
	return s.repo.DeleteAssignment(assignmentID, teacherID)
}

func (s *Service) Publish(assignmentID, teacherID int) error {
	return s.repo.SetStatus(assignmentID, teacherID, StatusPublished)
}

// Unpublish is only allowed if no student has submitted yet - once real
// activity exists, the teacher should Close (stop new submissions,
// keep it visible/gradable) or Archive instead.
func (s *Service) Unpublish(assignmentID, teacherID int) error {
	hasSubs, err := s.repo.HasSubmissions(assignmentID)
	if err != nil {
		return err
	}
	if hasSubs {
		return ErrHasSubmissions
	}
	return s.repo.SetStatus(assignmentID, teacherID, StatusUnpublished)
}

// Close stops an assignment from accepting new submissions while keeping
// it (and its existing submissions/analytics) visible - the step between
// Published and Archived.
func (s *Service) Close(assignmentID, teacherID int) error {
	return s.repo.SetStatus(assignmentID, teacherID, StatusClosed)
}

func (s *Service) Archive(assignmentID, teacherID int) error {
	return s.repo.SetStatus(assignmentID, teacherID, StatusArchived)
}

func (s *Service) GetByID(assignmentID int) (*Assignment, error) {
	return s.repo.GetByID(assignmentID)
}

func (s *Service) ListForTeacher(teacherID int) ([]Assignment, error) {
	return s.repo.ListForTeacher(teacherID)
}

func (s *Service) ListPublishedForSubject(subjectID, studentID int) ([]Assignment, error) {
	return s.repo.ListPublishedForSubject(subjectID, studentID)
}

func (s *Service) ListAllForAdmin() ([]Assignment, error) {
	return s.repo.ListAllForAdmin()
}

func (s *Service) GetAnalytics(teacherID *int) (*AnalyticsOverview, error) {
	return s.repo.GetAnalytics(teacherID)
}

// --- AI Assignment Generator (draft only - teacher edits before creating) ---

func (s *Service) GenerateAssignment(ctx context.Context, req GenerateAssignmentRequest) (*GeneratedAssignmentDraft, error) {
	subject, err := s.subjectsRepo.FindByID(0, req.SubjectID)
	if err != nil {
		return nil, err
	}

	difficulty := req.Difficulty
	if difficulty == "" {
		difficulty = "medium"
	}

	systemPrompt := "You are an expert curriculum designer. You output ONLY raw JSON - no markdown code fences, no preamble."
	userPrompt := fmt.Sprintf(`Design an open-ended written assignment about "%s" for the subject "%s", at %s difficulty.

Return ONLY a JSON object with exactly this shape:
{
  "title": "a short, specific assignment title",
  "description": "1-2 sentences describing what the assignment covers",
  "instructions": "clear step-by-step instructions for what the student should write/answer, 3-6 sentences",
  "estimated_minutes": 30
}

The assignment should require a written explanation (not multiple choice) - something an AI can meaningfully evaluate for concept understanding, completeness, and clarity. Output nothing but the JSON object.`, req.Topic, subject.Name, difficulty)

	messages := []ai.ChatCompletionMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	raw, err := s.groqClient.Chat(ctx, messages)
	if err != nil {
		return nil, err
	}

	clean := cleanJSONFence(raw)
	var draft GeneratedAssignmentDraft
	if err := json.Unmarshal([]byte(clean), &draft); err != nil {
		return nil, fmt.Errorf("invalid JSON from Groq: %w", err)
	}
	return &draft, nil
}

func cleanJSONFence(raw string) string {
	clean := strings.TrimSpace(raw)
	clean = strings.TrimPrefix(clean, "```json")
	clean = strings.TrimPrefix(clean, "```")
	clean = strings.TrimSuffix(clean, "```")
	return strings.TrimSpace(clean)
}

// --- Student: submission + AI evaluation ---

func (s *Service) SaveDraft(assignmentID, studentID int, text string) error {
	return s.repo.UpsertDraft(assignmentID, studentID, text)
}

// Submit finalizes the submission and immediately runs AI auto-evaluation
// (real Groq call, not a placeholder), then records the activity for the
// Learning Streak - the closest honest equivalent of "progress update"
// this app can support today without a dedicated assignment-progress model.
var ErrAssignmentNotOpen = fmt.Errorf("this assignment is no longer accepting submissions")

func (s *Service) Submit(ctx context.Context, assignmentID, studentID int, text string) (*Submission, error) {
	assignmentDetail, err := s.repo.GetByID(assignmentID)
	if err != nil {
		return nil, err
	}
	if assignmentDetail.Status != StatusPublished {
		return nil, ErrAssignmentNotOpen
	}

	submissionID, err := s.repo.SubmitFinal(assignmentID, studentID, text)
	if err != nil {
		return nil, err
	}

	if err := s.evaluateWithAI(ctx, submissionID, assignmentDetail, text); err != nil {
		// The submission is saved either way - evaluation failing shouldn't
		// lose the student's work. Logged so it's diagnosable, and the
		// student can retry via RetryEvaluation.
		log.Printf("[assignment] AI evaluation failed for submission %d: %v", submissionID, err)
	} else {
		_ = s.streakSvc.RecordActivity(studentID) // best-effort
	}

	return s.repo.GetSubmissionByID(submissionID)
}

// RetryEvaluation re-runs AI evaluation for a submission that never got
// evaluated (e.g. a transient Groq/JSON failure on first submit).
// Ownership-checked: a student can only retry their own submission.
func (s *Service) RetryEvaluation(ctx context.Context, submissionID, studentID int) (*Submission, error) {
	sub, err := s.repo.GetSubmissionByID(submissionID)
	if err != nil {
		return nil, err
	}
	if sub.StudentID != studentID {
		return nil, ErrForbidden
	}

	assignmentDetail, err := s.repo.GetByID(sub.AssignmentID)
	if err != nil {
		return nil, err
	}

	if err := s.evaluateWithAI(ctx, submissionID, assignmentDetail, sub.SubmissionText); err != nil {
		log.Printf("[assignment] AI evaluation retry failed for submission %d: %v", submissionID, err)
		return nil, err
	}
	_ = s.streakSvc.RecordActivity(studentID) // best-effort

	return s.repo.GetSubmissionByID(submissionID)
}

func (s *Service) evaluateWithAI(ctx context.Context, submissionID int, a *Assignment, submissionText string) error {
	systemPrompt := "You are an expert teacher grading a student's written assignment answer. You output ONLY raw JSON - no markdown code fences, no preamble."
	userPrompt := fmt.Sprintf(`Assignment title: "%s"
Instructions given to the student: "%s"
Maximum marks: %d

Student's submitted answer:
"""
%s
"""

Evaluate this answer and return ONLY a JSON object with exactly this shape:
{
  "score": 7,
  "strengths": ["short point", "short point"],
  "weaknesses": ["short point", "short point"],
  "missing_concepts": ["concept the answer should have covered but didn't"],
  "suggestions": "1-3 sentences of concrete, encouraging advice for improvement"
}

"score" is an integer from 0 to %d based on concept accuracy, completeness, and clarity. Be fair but rigorous - do not give full marks unless the answer genuinely deserves it. Output nothing but the JSON object.`,
		a.Title, a.Instructions, a.MaxMarks, submissionText, a.MaxMarks)

	messages := []ai.ChatCompletionMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	raw, err := s.groqClient.Chat(ctx, messages)
	if err != nil {
		return err
	}

	clean := cleanJSONFence(raw)
	var result struct {
		Score           int      `json:"score"`
		Strengths       []string `json:"strengths"`
		Weaknesses      []string `json:"weaknesses"`
		MissingConcepts []string `json:"missing_concepts"`
		Suggestions     string   `json:"suggestions"`
	}
	if err := json.Unmarshal([]byte(clean), &result); err != nil {
		return fmt.Errorf("invalid JSON from Groq: %w", err)
	}

	return s.repo.SaveAIEvaluation(submissionID, result.Score, a.MaxMarks, result.Strengths, result.Weaknesses, result.MissingConcepts, result.Suggestions)
}

func (s *Service) GetMySubmission(assignmentID, studentID int) (*Submission, error) {
	return s.repo.GetSubmissionByAssignmentAndStudent(assignmentID, studentID)
}

// --- Teacher: review queue ---

func (s *Service) ListSubmissionsForAssignment(assignmentID, teacherID int) ([]Submission, error) {
	return s.repo.ListSubmissionsForAssignment(assignmentID, teacherID)
}

func (s *Service) TeacherReview(submissionID, teacherID int, req TeacherReviewRequest) error {
	return s.repo.SaveTeacherReview(submissionID, teacherID, req.OverrideScore, req.Feedback)
}
