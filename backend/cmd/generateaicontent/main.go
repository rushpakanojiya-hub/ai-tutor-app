// Command generateaicontent is a one-off backfill tool: it finds every
// lesson with no lesson_ai_content row yet, asks Groq to generate a full
// explanation/summary/key points/examples/practice questions/quiz package
// as structured JSON, and inserts it - so lessons seeded without
// hand-written content (e.g. Competitive Exams, Biology, Geography, etc.)
// get the same "AI Explanation" + quiz experience as the original lessons.
//
// Run once from the backend/ folder:
//
//	go run cmd/generateaicontent/main.go
//
// Safe to re-run: it only processes lessons that still have zero AI content.
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/database"
	"ai-tutor-backend/internal/ai"
)

type lessonRow struct {
	ID          int
	Title       string
	Description string
	SubjectName string
}

type quizQuestion struct {
	Question      string   `json:"question"`
	Options       []string `json:"options"`
	CorrectOption int      `json:"correct_option"`
}

type aiContentPayload struct {
	Explanation       string         `json:"explanation"`
	Summary           string         `json:"summary"`
	KeyPoints         []string       `json:"key_points"`
	Examples          []string       `json:"examples"`
	PracticeQuestions []string       `json:"practice_questions"`
	Quiz              []quizQuestion `json:"quiz"`
}

func main() {
	cfg := configs.LoadConfig()
	db := database.Connect(cfg)
	defer db.Close()

	groqClient := ai.NewGroqClient(cfg.GroqAPIKey, cfg.GroqAPIURL, cfg.GroqModel)

	lessons, err := findLessonsMissingAIContent(db)
	if err != nil {
		log.Fatalf("failed to query lessons: %v", err)
	}

	if len(lessons) == 0 {
		fmt.Println("No lessons are missing AI content. Nothing to do.")
		return
	}

	fmt.Printf("Found %d lesson(s) missing AI content. Generating...\n\n", len(lessons))

	for i, lesson := range lessons {
		fmt.Printf("[%d/%d] %s (%s)... ", i+1, len(lessons), lesson.Title, lesson.SubjectName)

		payload, err := generateAIContent(groqClient, lesson)
		if err != nil {
			fmt.Printf("FAILED (Groq): %v\n", err)
			continue
		}

		if err := insertAIContent(db, lesson.ID, payload); err != nil {
			fmt.Printf("FAILED (DB): %v\n", err)
			continue
		}

		fmt.Println("done")
		time.Sleep(3 * time.Second) // be gentle with Groq's rate limits
	}

	fmt.Println("\nAll done.")
}

func findLessonsMissingAIContent(db *sql.DB) ([]lessonRow, error) {
	query := `
		SELECT l.id, l.title, COALESCE(l.description, ''), s.name
		FROM lessons l
		JOIN subjects s ON s.id = l.subject_id
		LEFT JOIN lesson_ai_content ac ON ac.lesson_id = l.id
		WHERE ac.id IS NULL
		ORDER BY l.id`

	rows, err := db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []lessonRow
	for rows.Next() {
		var l lessonRow
		if err := rows.Scan(&l.ID, &l.Title, &l.Description, &l.SubjectName); err != nil {
			return nil, err
		}
		result = append(result, l)
	}
	return result, rows.Err()
}

func generateAIContent(client *ai.GroqClient, lesson lessonRow) (*aiContentPayload, error) {
	systemPrompt := `You are an expert exam-prep content writer. You output ONLY raw JSON - no markdown code fences, no preamble, no explanation outside the JSON.`

	userPrompt := fmt.Sprintf(`Generate learning content for the lesson "%s" (%s), part of "%s".

Return ONLY a JSON object with exactly this shape:
{
  "explanation": "a clear 3-5 sentence explanation of the topic",
  "summary": "a 1-2 sentence summary",
  "key_points": ["4-5 short key point strings"],
  "examples": ["2-3 concrete example strings"],
  "practice_questions": ["2-3 open-ended practice question strings"],
  "quiz": [
    {"question": "...", "options": ["...", "...", "...", "..."], "correct_option": 0}
  ]
}

The quiz array must have exactly 3 multiple-choice questions, each with exactly 4 options, and correct_option as the 0-based index of the right answer. Output nothing but the JSON object.`, lesson.Title, lesson.Description, lesson.SubjectName)

	messages := []ai.ChatCompletionMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	raw, err := client.Chat(ctx, messages)
	if err != nil {
		return nil, err
	}

	clean := strings.TrimSpace(raw)
	clean = strings.TrimPrefix(clean, "```json")
	clean = strings.TrimPrefix(clean, "```")
	clean = strings.TrimSuffix(clean, "```")
	clean = strings.TrimSpace(clean)

	var payload aiContentPayload
	if err := json.Unmarshal([]byte(clean), &payload); err != nil {
		return nil, fmt.Errorf("invalid JSON from Groq: %w", err)
	}
	return &payload, nil
}

func insertAIContent(db *sql.DB, lessonID int, payload *aiContentPayload) error {
	keyPoints, err := json.Marshal(payload.KeyPoints)
	if err != nil {
		return err
	}
	examples, err := json.Marshal(payload.Examples)
	if err != nil {
		return err
	}
	practiceQuestions, err := json.Marshal(payload.PracticeQuestions)
	if err != nil {
		return err
	}
	quiz, err := json.Marshal(payload.Quiz)
	if err != nil {
		return err
	}

	_, err = db.Exec(`
		INSERT INTO lesson_ai_content
			(lesson_id, explanation, summary, key_points, examples, practice_questions, quiz_json)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (lesson_id) DO UPDATE SET
			explanation = EXCLUDED.explanation,
			summary = EXCLUDED.summary,
			key_points = EXCLUDED.key_points,
			examples = EXCLUDED.examples,
			practice_questions = EXCLUDED.practice_questions,
			quiz_json = EXCLUDED.quiz_json,
			updated_at = NOW()`,
		lessonID, payload.Explanation, payload.Summary, keyPoints, examples, practiceQuestions, quiz,
	)
	return err
}
