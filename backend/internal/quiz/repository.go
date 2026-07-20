package quiz

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"sort"
	"time"
)

// Repository handles direct SQL access for quiz attempts and analytics.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a quiz Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// LessonQuizQuestion mirrors one entry from lesson_ai_content.quiz_json -
// always single-correct MCQ, unchanged from before.
type LessonQuizQuestion struct {
	Question      string   `json:"question"`
	Options       []string `json:"options"`
	CorrectOption int      `json:"correct_option"`
}

// GetLessonQuiz fetches the quiz questions stored for a lesson, or nil if
// the lesson has no AI content / quiz yet.
func (r *Repository) GetLessonQuiz(lessonID int) ([]LessonQuizQuestion, error) {
	var raw []byte
	err := r.db.QueryRow(`SELECT quiz_json FROM lesson_ai_content WHERE lesson_id = $1`, lessonID).Scan(&raw)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var questions []LessonQuizQuestion
	if err := json.Unmarshal(raw, &questions); err != nil {
		return nil, err
	}
	return questions, nil
}

// GetLessonSubjectID resolves a lesson's subject_id, to tag the attempt
// for subject-level analytics.
func (r *Repository) GetLessonSubjectID(lessonID int) (int, error) {
	var subjectID int
	err := r.db.QueryRow(`SELECT subject_id FROM lessons WHERE id = $1`, lessonID).Scan(&subjectID)
	return subjectID, err
}

// --- Generated-quiz answer-key session store ------------------------------
//
// Fixes audit CRITICAL #3: freeform quizzes previously had no server-side
// record of the correct answers, so grading trusted whatever "correct_*"
// fields the client echoed back. GenerateQuiz now persists the real,
// AI-generated answer key here (keyed by an unguessable session ID) at
// /generate time, and SubmitFreeformAttempt reads it back at grading time -
// the client is never trusted with the answer key before it submits.

// SaveGeneratedQuiz persists the full (answer-key-included) question set
// for a freeform quiz, returning a new unguessable session ID.
func (r *Repository) SaveGeneratedQuiz(userID int, topic string, subjectID *int, questions []FreeformQuestion, ttl time.Duration) (string, error) {
	sessionID, err := newSessionID()
	if err != nil {
		return "", err
	}

	payload, err := json.Marshal(questions)
	if err != nil {
		return "", err
	}

	now := time.Now().UTC()
	const q = `
		INSERT INTO quiz_generated_sessions (id, user_id, topic, subject_id, questions_json, created_at, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`
	if _, err := r.db.Exec(q, sessionID, userID, topic, subjectID, payload, now, now.Add(ttl)); err != nil {
		return "", err
	}
	return sessionID, nil
}

// GetGeneratedQuiz looks up a previously-generated answer key by session
// ID, verifying it belongs to userID and hasn't expired. Returns
// ErrQuizSessionNotFound (never a raw sql.ErrNoRows or DB detail) for any
// "doesn't exist / wrong user / expired" case, so a caller can't use the
// error to probe for valid session IDs belonging to other users.
func (r *Repository) GetGeneratedQuiz(sessionID string, userID int) ([]FreeformQuestion, *int, error) {
	const q = `
		SELECT subject_id, questions_json
		FROM quiz_generated_sessions
		WHERE id = $1 AND user_id = $2 AND expires_at > now()`

	var subjectID sql.NullInt64
	var raw []byte
	err := r.db.QueryRow(q, sessionID, userID).Scan(&subjectID, &raw)
	if err == sql.ErrNoRows {
		return nil, nil, ErrQuizSessionNotFound
	}
	if err != nil {
		return nil, nil, err
	}

	var questions []FreeformQuestion
	if err := json.Unmarshal(raw, &questions); err != nil {
		return nil, nil, err
	}

	var subjectIDPtr *int
	if subjectID.Valid {
		v := int(subjectID.Int64)
		subjectIDPtr = &v
	}
	return questions, subjectIDPtr, nil
}

// DeleteGeneratedQuiz removes a session after it's been graded (single-use)
// so the same server-held answer key can't be resubmitted repeatedly.
func (r *Repository) DeleteGeneratedQuiz(sessionID string) error {
	_, err := r.db.Exec(`DELETE FROM quiz_generated_sessions WHERE id = $1`, sessionID)
	return err
}

func newSessionID() (string, error) {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// --- Attempts --------------------------------------------------------------

// nullableJSON marshals a slice to JSON, returning nil (-> SQL NULL) for
// an empty/nil slice instead of the literal string "[]", so optional
// per-type columns (correct_options, selected_options) stay genuinely
// empty for question types that don't use them.
func nullableJSON(v interface{}) ([]byte, error) {
	switch t := v.(type) {
	case []int:
		if len(t) == 0 {
			return nil, nil
		}
	case []string:
		if len(t) == 0 {
			return nil, nil
		}
	}
	return json.Marshal(v)
}

// SaveAttempt inserts the attempt row and its per-question answers in one
// transaction, returning the new attempt ID.
func (r *Repository) SaveAttempt(userID int, lessonID, subjectID *int, topic string, timeTakenSeconds int, answers []AttemptAnswer) (int, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	correctCount := 0
	for _, a := range answers {
		if a.IsCorrect {
			correctCount++
		}
	}
	total := len(answers)
	scorePercent := 0
	if total > 0 {
		scorePercent = (correctCount * 100) / total
	}

	var attemptID int
	err = tx.QueryRow(`
		INSERT INTO quiz_attempts (user_id, lesson_id, subject_id, topic, total_questions, correct_count, score_percent, time_taken_seconds)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id`,
		userID, lessonID, subjectID, topic, total, correctCount, scorePercent, timeTakenSeconds,
	).Scan(&attemptID)
	if err != nil {
		return 0, err
	}

	for _, a := range answers {
		optionsJSON, err := nullableJSON(a.Options)
		if err != nil {
			return 0, err
		}
		correctOptionsJSON, err := nullableJSON(a.CorrectOptions)
		if err != nil {
			return 0, err
		}
		selectedOptionsJSON, err := nullableJSON(a.SelectedOptions)
		if err != nil {
			return 0, err
		}

		questionType := a.QuestionType
		if questionType == "" {
			questionType = QuestionTypeSingleMCQ
		}

		res, err := tx.Exec(`
			INSERT INTO quiz_attempt_answers
				(attempt_id, question_index, question_type, question_text, options,
				 selected_option, correct_option, correct_options, selected_options,
				 submitted_text, correct_text, hint, explanation, difficulty_score, is_correct)
			VALUES ($1, $2, $3, $4, COALESCE($5, '[]'::jsonb), $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
			attemptID, a.QuestionIndex, questionType, a.QuestionText, optionsJSON,
			a.SelectedOption, a.CorrectOption, correctOptionsJSON, selectedOptionsJSON,
			a.SubmittedText, a.CorrectText, a.Hint, a.Explanation, nullIfZero(a.DifficultyScore), a.IsCorrect,
		)
		if err != nil {
			return 0, err
		}
		if n, rerr := res.RowsAffected(); rerr == nil && n == 0 {
			return 0, sql.ErrNoRows
		}
	}

	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return attemptID, nil
}

func nullIfZero(n int) interface{} {
	if n == 0 {
		return nil
	}
	return n
}

// ListAttempts returns a user's attempt history (most recent first),
// optionally filtered by lessonID (pass 0 for no filter).
func (r *Repository) ListAttempts(userID, lessonID int) ([]Attempt, error) {
	query := `
		SELECT id, user_id, lesson_id, subject_id, topic, total_questions, correct_count, score_percent, time_taken_seconds, created_at
		FROM quiz_attempts
		WHERE user_id = $1`
	args := []interface{}{userID}
	if lessonID > 0 {
		query += ` AND lesson_id = $2`
		args = append(args, lessonID)
	}
	query += ` ORDER BY created_at DESC`

	rows, err := r.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Attempt
	for rows.Next() {
		var a Attempt
		if err := rows.Scan(&a.ID, &a.UserID, &a.LessonID, &a.SubjectID, &a.Topic, &a.TotalQuestions, &a.CorrectCount, &a.ScorePercent, &a.TimeTakenSeconds, &a.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, a)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

// GetAttemptWithAnswers returns one attempt (verifying ownership) plus its
// full per-question breakdown, for the results/review screen.
func (r *Repository) GetAttemptWithAnswers(userID, attemptID int) (*AttemptWithAnswers, error) {
	var a Attempt
	err := r.db.QueryRow(`
		SELECT id, user_id, lesson_id, subject_id, topic, total_questions, correct_count, score_percent, time_taken_seconds, created_at
		FROM quiz_attempts WHERE id = $1 AND user_id = $2`, attemptID, userID,
	).Scan(&a.ID, &a.UserID, &a.LessonID, &a.SubjectID, &a.Topic, &a.TotalQuestions, &a.CorrectCount, &a.ScorePercent, &a.TimeTakenSeconds, &a.CreatedAt)
	if err != nil {
		return nil, err
	}

	rows, err := r.db.Query(`
		SELECT id, attempt_id, question_index, question_type, question_text, options,
		       selected_option, correct_option, correct_options, selected_options,
		       submitted_text, correct_text, hint, explanation, difficulty_score, is_correct
		FROM quiz_attempt_answers WHERE attempt_id = $1 ORDER BY question_index`, attemptID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var answers []AttemptAnswer
	for rows.Next() {
		var ans AttemptAnswer
		var optionsRaw, correctOptionsRaw, selectedOptionsRaw []byte
		var submittedText, correctText, hint, explanation sql.NullString
		var difficultyScore sql.NullInt64

		if err := rows.Scan(
			&ans.ID, &ans.AttemptID, &ans.QuestionIndex, &ans.QuestionType, &ans.QuestionText, &optionsRaw,
			&ans.SelectedOption, &ans.CorrectOption, &correctOptionsRaw, &selectedOptionsRaw,
			&submittedText, &correctText, &hint, &explanation, &difficultyScore, &ans.IsCorrect,
		); err != nil {
			return nil, err
		}

		if len(optionsRaw) > 0 {
			_ = json.Unmarshal(optionsRaw, &ans.Options)
		}
		if len(correctOptionsRaw) > 0 {
			_ = json.Unmarshal(correctOptionsRaw, &ans.CorrectOptions)
		}
		if len(selectedOptionsRaw) > 0 {
			_ = json.Unmarshal(selectedOptionsRaw, &ans.SelectedOptions)
		}
		ans.SubmittedText = submittedText.String
		ans.CorrectText = correctText.String
		ans.Hint = hint.String
		ans.Explanation = explanation.String
		if difficultyScore.Valid {
			ans.DifficultyScore = int(difficultyScore.Int64)
		}

		answers = append(answers, ans)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return &AttemptWithAnswers{Attempt: a, Answers: answers}, nil
}

// GetAnalytics computes overall + per-subject accuracy from real attempt
// data - nothing here is fabricated or hardcoded. Date bucketing for the
// weekly trend is computed in Go using UTC (rather than relying solely on
// Postgres's CURRENT_DATE, which follows the session/server timezone) so
// "today" is consistent with the rest of the app's UTC-based logic (streaks,
// etc).
func (r *Repository) GetAnalytics(userID int) (*Analytics, error) {
	analytics := &Analytics{}

	var totalCorrect, totalQuestions int
	err := r.db.QueryRow(`
		SELECT COUNT(*), COALESCE(SUM(correct_count), 0), COALESCE(SUM(total_questions), 0)
		FROM quiz_attempts WHERE user_id = $1`, userID,
	).Scan(&analytics.TotalAttempts, &totalCorrect, &totalQuestions)
	if err != nil {
		return nil, err
	}
	if totalQuestions > 0 {
		analytics.OverallAccuracy = (float64(totalCorrect) / float64(totalQuestions)) * 100
	}

	// Passed/failed (60% threshold), average score, highest score - all
	// derived directly from each attempt's stored score_percent.
	const passThreshold = 60
	scoreRows, err := r.db.Query(`SELECT score_percent FROM quiz_attempts WHERE user_id = $1`, userID)
	if err != nil {
		return nil, err
	}
	var scoreSum, scoreCount, highest int
	for scoreRows.Next() {
		var score int
		if err := scoreRows.Scan(&score); err != nil {
			scoreRows.Close()
			return nil, err
		}
		scoreSum += score
		scoreCount++
		if score > highest {
			highest = score
		}
		if score >= passThreshold {
			analytics.PassedCount++
		} else {
			analytics.FailedCount++
		}
	}
	if err := scoreRows.Err(); err != nil {
		scoreRows.Close()
		return nil, err
	}
	scoreRows.Close()
	if scoreCount > 0 {
		analytics.AverageScore = float64(scoreSum) / float64(scoreCount)
	}
	analytics.HighestScore = highest

	// Weekly trend: one accuracy point per day for the last 7 UTC days.
	// The 7-day window boundary is computed here in Go (UTC) and passed as
	// a bound parameter, instead of letting Postgres's CURRENT_DATE (which
	// follows the DB server's configured timezone) decide what "today" is.
	today := time.Now().UTC().Truncate(24 * time.Hour)
	windowStart := today.AddDate(0, 0, -6)

	trendRows, err := r.db.Query(`
		SELECT (created_at AT TIME ZONE 'utc')::date AS day, COUNT(*), COALESCE(SUM(correct_count), 0), COALESCE(SUM(total_questions), 0)
		FROM quiz_attempts
		WHERE user_id = $1 AND created_at >= $2
		GROUP BY day
		ORDER BY day`, userID, windowStart)
	if err != nil {
		return nil, err
	}
	dayMap := map[string]DayAccuracy{}
	for trendRows.Next() {
		var date time.Time
		var attempts, correct, questions int
		if err := trendRows.Scan(&date, &attempts, &correct, &questions); err != nil {
			trendRows.Close()
			return nil, err
		}
		acc := 0.0
		if questions > 0 {
			acc = (float64(correct) / float64(questions)) * 100
		}
		key := date.Format("2006-01-02")
		dayMap[key] = DayAccuracy{Date: key, Accuracy: acc, Attempts: attempts}
	}
	if err := trendRows.Err(); err != nil {
		trendRows.Close()
		return nil, err
	}
	trendRows.Close()

	for i := 6; i >= 0; i-- {
		day := today.AddDate(0, 0, -i)
		key := day.Format("2006-01-02")
		if d, ok := dayMap[key]; ok {
			analytics.WeeklyTrend = append(analytics.WeeklyTrend, d)
		} else {
			analytics.WeeklyTrend = append(analytics.WeeklyTrend, DayAccuracy{Date: key, Accuracy: 0, Attempts: 0})
		}
	}

	rows, err := r.db.Query(`
		SELECT s.id, s.name, COUNT(qa.id), COALESCE(SUM(qa.correct_count), 0), COALESCE(SUM(qa.total_questions), 0)
		FROM quiz_attempts qa
		JOIN subjects s ON s.id = qa.subject_id
		WHERE qa.user_id = $1
		GROUP BY s.id, s.name
		ORDER BY s.name`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var sa SubjectAccuracy
		var correct, questions int
		if err := rows.Scan(&sa.SubjectID, &sa.SubjectName, &sa.Attempts, &correct, &questions); err != nil {
			return nil, err
		}
		if questions > 0 {
			sa.Accuracy = (float64(correct) / float64(questions)) * 100
		}
		analytics.BySubject = append(analytics.BySubject, sa)
		if sa.Accuracy < 60 {
			analytics.WeakTopics = append(analytics.WeakTopics, sa)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	sort.Slice(analytics.WeakTopics, func(i, j int) bool {
		return analytics.WeakTopics[i].Accuracy < analytics.WeakTopics[j].Accuracy
	})

	return analytics, nil
}
