package ai

import (
	"context"
	"errors"
	"log"

	"ai-tutor-backend/internal/streak"
	"ai-tutor-backend/internal/subjects"
)

// ErrAINotConfigured is returned when GROQ_API_KEY is missing - surfaced
// as a clear "AI Tutor isn't set up yet" message rather than a raw network error.
var ErrAINotConfigured = errors.New("AI Tutor is not configured on the server")

// Service contains the business logic for AI Tutor chat: resolving/
// creating sessions, loading context, calling Groq, and persisting the
// conversation. All language generation is delegated to GroqClient -
// nothing here does keyword matching or static responses.
type Service struct {
	repo         *Repository
	subjectsRepo *subjects.Repository
	groqClient   *GroqClient
	streakSvc    *streak.Service
}

// NewService wires a Repository, the subjects Repository (for subject-name
// lookups used in the prompt), a GroqClient, and the shared streak Service
// into an ai Service.
func NewService(repo *Repository, subjectsRepo *subjects.Repository, groqClient *GroqClient, streakSvc *streak.Service) *Service {
	return &Service{repo: repo, subjectsRepo: subjectsRepo, groqClient: groqClient, streakSvc: streakSvc}
}

// resolveSession finds an existing session (verifying ownership) or
// creates a new one, returning its ID.
func (s *Service) resolveSession(userID int, req ChatRequest) (int, error) {
	if req.SessionID != nil {
		session, err := s.repo.FindSessionByID(userID, *req.SessionID)
		if err != nil {
			return 0, err
		}
		return session.ID, nil
	}

	title := truncateTitle(req.Message, 50)
	return s.repo.CreateSession(userID, req.SubjectID, title)
}

// truncateTitle cuts a session title to at most maxRunes RUNES (not
// bytes) - QA fix ("UTF-8 title truncation"): the previous version did
// title[:50], a BYTE slice. For Hindi/Marathi messages (which this app
// explicitly supports), a multi-byte UTF-8 character sitting right at
// that boundary got sliced in half, producing a mangled/invalid title.
func truncateTitle(message string, maxRunes int) string {
	runes := []rune(message)
	if len(runes) <= maxRunes {
		return message
	}
	return string(runes[:maxRunes]) + "..."
}

// subjectName resolves a subject_id into its display name for the system
// prompt (e.g. "Mathematics") - returns "" if none was given or it can't
// be found, so a chat without a subject still works normally.
func (s *Service) subjectName(subjectID *int) string {
	if subjectID == nil {
		return ""
	}
	subject, err := s.subjectsRepo.FindByID(0, *subjectID)
	if err != nil {
		return ""
	}
	return subject.Name
}

// Chat handles one turn: resolves/creates the session, loads the last 10
// messages as context, sends everything to Groq, saves both the
// student's message and the AI's reply, and returns the reply.
//
// QA fix ("Roll back failed AI messages" / "Preserve chat consistency"):
// the student's message used to be saved to the DB BEFORE calling Groq,
// with no cleanup if that call then failed. If Groq fails, the just-saved
// user message is deleted so the session's history stays consistent.
//
// BUG FIX (this pass): after a SUCCESSFUL (and billed) Groq call, saving
// the assistant's reply (AddMessage) or touching the session
// (TouchSession) could still fail on a transient DB hiccup - and the
// previous code treated that as a hard failure, returning an error and
// discarding the reply entirely. The student would see "something went
// wrong" despite the AI Tutor having already generated a perfectly good
// answer (that Groq call cost real money). These two persistence steps
// are now best-effort: failures are logged, but the reply is still
// returned to the caller either way. Worst case, that one reply doesn't
// appear in the session's history on reload - much better than losing it
// outright.
func (s *Service) Chat(ctx context.Context, userID int, req ChatRequest) (*ChatResponse, error) {
	sessionID, err := s.resolveSession(userID, req)
	if err != nil {
		return nil, err
	}

	// Load history BEFORE saving the current message, so it isn't
	// double-counted when prompt_builder.go appends req.Message itself.
	history, err := s.repo.RecentMessages(sessionID, maxContextMessages)
	if err != nil {
		return nil, err
	}

	userMessageID, err := s.repo.AddMessage(sessionID, "user", req.Message)
	if err != nil {
		return nil, err
	}

	subjectName := s.subjectName(req.SubjectID)
	messages := buildMessages(subjectName, req.Language, req.Mode, history, req.Message)

	reply, err := s.groqClient.Chat(ctx, messages)
	if err != nil {
		if rollbackErr := s.repo.DeleteMessage(userMessageID); rollbackErr != nil {
			log.Printf("[ai] failed to roll back orphaned user message %d after Groq error: %v", userMessageID, rollbackErr)
		}
		if errors.Is(err, ErrNoAPIKey) {
			return nil, ErrAINotConfigured
		}
		return nil, err
	}

	if _, err := s.repo.AddMessage(sessionID, "assistant", reply); err != nil {
		log.Printf("[ai] failed to persist assistant reply for session %d (reply still returned to caller): %v", sessionID, err)
	}
	if err := s.repo.TouchSession(sessionID); err != nil {
		log.Printf("[ai] failed to touch session %d after reply (non-fatal): %v", sessionID, err)
	}
	_ = s.streakSvc.RecordActivity(userID) // best-effort

	return &ChatResponse{SessionID: sessionID, Reply: reply}, nil
}

// ListSessions returns a user's chat session history.
func (s *Service) ListSessions(userID int) ([]ChatSession, error) {
	return s.repo.ListSessions(userID)
}

// GetSession returns a session with all of its messages.
func (s *Service) GetSession(userID, sessionID int) (*SessionWithMessages, error) {
	session, err := s.repo.FindSessionByID(userID, sessionID)
	if err != nil {
		return nil, err
	}
	messages, err := s.repo.ListMessages(sessionID)
	if err != nil {
		return nil, err
	}
	return &SessionWithMessages{ChatSession: *session, Messages: messages}, nil
}

// DeleteSession removes a session.
func (s *Service) DeleteSession(userID, sessionID int) error {
	return s.repo.DeleteSession(userID, sessionID)
}
