package quiz

import (
	"database/sql"
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

		_, err = tx.Exec(`
			INSERT INTO quiz_attempt_answers
				(attempt_id, question_index, question_type, question_text, options,
				 selected_option, correct_option, correct_options, selected_options,
				 submitted_text, correct_text, hint, explanation, difficulty_score, is_correct)
			VALUES ($1, $2, $3, $4, COALESCE($5, '[]'), $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
			attemptID, a.QuestionIndex, questionType, a.QuestionText, optionsJSON,
			a.SelectedOption, a.CorrectOption, correctOptionsJSON, selectedOptionsJSON,
			a.SubmittedText, a.CorrectText, a.Hint, a.Explanation, nullIfZero(a.DifficultyScore), a.IsCorrect,
		)
		if err != nil {
			return 0, err
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

	return &AttemptWithAnswers{Attempt: a, Answers: answers}, nil
}

// GetAnalytics computes overall + per-subject accuracy from real attempt
// data - nothing here is fabricated or hardcoded.
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
	scoreRows.Close()
	if scoreCount > 0 {
		analytics.AverageScore = float64(scoreSum) / float64(scoreCount)
	}
	analytics.HighestScore = highest

	// Weekly trend: one accuracy point per day for the last 7 days.
	trendRows, err := r.db.Query(`
		SELECT created_at::date, COUNT(*), COALESCE(SUM(correct_count), 0), COALESCE(SUM(total_questions), 0)
		FROM quiz_attempts
		WHERE user_id = $1 AND created_at >= CURRENT_DATE - INTERVAL '6 days'
		GROUP BY created_at::date
		ORDER BY created_at::date`, userID)
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
	trendRows.Close()

	today := time.Now()
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

	sort.Slice(analytics.WeakTopics, func(i, j int) bool {
		return analytics.WeakTopics[i].Accuracy < analytics.WeakTopics[j].Accuracy
	})

	return analytics, nil
}
