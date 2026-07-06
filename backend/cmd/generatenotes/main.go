// Command generatenotes is a one-off backfill tool: it finds every lesson
// that has no notes row yet, asks Groq to write structured study notes for
// it, renders those notes as a real PDF under backend/static/notes/, and
// inserts the matching notes row - so lessons seeded without hand-written
// content (e.g. the Competitive Exams subjects) get real, readable notes
// instead of staying empty.
//
// Run once from the backend/ folder after `go get github.com/jung-kurt/gofpdf`:
//
//	go run cmd/generatenotes/main.go
//
// Safe to re-run: it only processes lessons that still have zero notes.
package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"regexp"
	"strings"
	"time"

	"github.com/jung-kurt/gofpdf"

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

func main() {
	cfg := configs.LoadConfig()
	db := database.Connect(cfg)
	defer db.Close()

	groqClient := ai.NewGroqClient(cfg.GroqAPIKey, cfg.GroqAPIURL, cfg.GroqModel)

	lessons, err := findLessonsMissingNotes(db)
	if err != nil {
		log.Fatalf("failed to query lessons: %v", err)
	}

	if len(lessons) == 0 {
		fmt.Println("No lessons are missing notes. Nothing to do.")
		return
	}

	fmt.Printf("Found %d lesson(s) missing notes. Generating...\n\n", len(lessons))

	for i, lesson := range lessons {
		fmt.Printf("[%d/%d] %s (%s)... ", i+1, len(lessons), lesson.Title, lesson.SubjectName)

		body, err := generateNotesText(groqClient, lesson)
		if err != nil {
			fmt.Printf("FAILED (Groq): %v\n", err)
			continue
		}

		pdfPath, publicURL := notesPaths(lesson)
		if err := writeNotesPDF(pdfPath, lesson.Title, lesson.SubjectName, body); err != nil {
			fmt.Printf("FAILED (PDF): %v\n", err)
			continue
		}

		if err := insertNotesRow(db, lesson.ID, lesson.Title+" Notes", publicURL); err != nil {
			fmt.Printf("FAILED (DB): %v\n", err)
			continue
		}

		fmt.Println("done")
		time.Sleep(3 * time.Second) // be gentle with Groq's rate limits
	}

	fmt.Println("\nAll done.")
}

func findLessonsMissingNotes(db *sql.DB) ([]lessonRow, error) {
	query := `
		SELECT l.id, l.title, COALESCE(l.description, ''), s.name
		FROM lessons l
		JOIN subjects s ON s.id = l.subject_id
		LEFT JOIN notes n ON n.lesson_id = l.id
		WHERE n.id IS NULL
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

func generateNotesText(client *ai.GroqClient, lesson lessonRow) (string, error) {
	systemPrompt := "You are an expert exam-prep content writer. Write clear, accurate, well-structured study notes for students."
	userPrompt := fmt.Sprintf(`Write study notes for the topic "%s" (%s), part of preparation for "%s".

Format rules:
- Start each major heading with "# "
- Start sub-headings with "## "
- Use "- " for bullet points
- Plain paragraphs for explanations, no other markdown

Keep it focused, accurate, and exam-relevant. Around 400-600 words.`, lesson.Title, lesson.Description, lesson.SubjectName)

	messages := []ai.ChatCompletionMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	return client.Chat(ctx, messages)
}

var slugPattern = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(s string) string {
	s = strings.ToLower(s)
	s = slugPattern.ReplaceAllString(s, "-")
	return strings.Trim(s, "-")
}

func notesPaths(lesson lessonRow) (filePath, publicURL string) {
	filename := fmt.Sprintf("%s-%s.pdf", slugify(lesson.SubjectName), slugify(lesson.Title))
	return "./static/notes/" + filename, "/static/notes/" + filename
}

// writeNotesPDF renders plain-text/lightweight-markdown notes into a real
// PDF: "# " lines become large headings, "## " lines become sub-headings,
// everything else is body text (bold-marker "**" stripped since gofpdf's
// core fonts don't do inline bold easily).
func writeNotesPDF(path, title, subject, body string) error {
	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.AddPage()

	pdf.SetFont("Arial", "B", 16)
	pdf.MultiCell(0, 10, title, "", "L", false)

	pdf.SetFont("Arial", "I", 11)
	pdf.MultiCell(0, 8, subject, "", "L", false)
	pdf.Ln(4)

	pdf.SetFont("Arial", "", 11)

	for _, rawLine := range strings.Split(body, "\n") {
		line := strings.TrimSpace(rawLine)
		switch {
		case line == "":
			pdf.Ln(3)
		case strings.HasPrefix(line, "# "):
			pdf.SetFont("Arial", "B", 14)
			pdf.MultiCell(0, 8, strings.TrimPrefix(line, "# "), "", "L", false)
			pdf.SetFont("Arial", "", 11)
		case strings.HasPrefix(line, "## "):
			pdf.SetFont("Arial", "B", 12)
			pdf.MultiCell(0, 7, strings.TrimPrefix(line, "## "), "", "L", false)
			pdf.SetFont("Arial", "", 11)
		default:
			clean := strings.ReplaceAll(line, "**", "")
			pdf.MultiCell(0, 6, clean, "", "L", false)
		}
	}

	return pdf.OutputFileAndClose(path)
}

func insertNotesRow(db *sql.DB, lessonID int, title, pdfURL string) error {
	_, err := db.Exec(`INSERT INTO notes (lesson_id, title, pdf_url) VALUES ($1, $2, $3)`, lessonID, title, pdfURL)
	return err
}
