$files = @{}
$files['main.go'] = @'
// AI Tutor Backend — Day 2 (Course & Learning Management added)
// Boots the Gin server, connects to PostgreSQL, and wires up all modules
// using Clean Architecture (handler -> service -> repository -> model).
package main

import (
	"fmt"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/database"
	"ai-tutor-backend/internal/ai"
	"ai-tutor-backend/internal/aicontent"
	"ai-tutor-backend/internal/auth"
	"ai-tutor-backend/internal/categories"
	"ai-tutor-backend/internal/lessons"
	"ai-tutor-backend/internal/middleware"
	"ai-tutor-backend/internal/notes"
	"ai-tutor-backend/internal/progress"
	"ai-tutor-backend/internal/recommendations"
	"ai-tutor-backend/internal/search"
	"ai-tutor-backend/internal/subjects"
	"ai-tutor-backend/internal/users"
	"ai-tutor-backend/pkg/logger"
)

func main() {
	cfg := configs.LoadConfig()
	gin.SetMode(cfg.GinMode)

	db := database.Connect(cfg)
	defer db.Close()

	router := gin.Default()
	router.Use(middleware.CORSMiddleware())

	// Serves lesson PDF notes from backend/static/notes/*.pdf as
	// http://<host>:<port>/static/notes/<file>.pdf — real, self-hosted
	// content instead of random third-party URLs (see migration 000014).
	router.Static("/static", "./static")

	authMiddleware := middleware.AuthMiddleware(cfg.JWTSecret)

	// --- Day 1: auth + users (unchanged) ---
	authRepo := auth.NewRepository(db)
	authService := auth.NewService(authRepo, cfg)
	authHandler := auth.NewHandler(authService)

	usersRepo := users.NewRepository(db)
	usersService := users.NewService(usersRepo)
	usersHandler := users.NewHandler(usersService)

	// --- Day 2: course & learning management ---
	categoriesRepo := categories.NewRepository(db)
	categoriesService := categories.NewService(categoriesRepo)
	categoriesHandler := categories.NewHandler(categoriesService)

	subjectsRepo := subjects.NewRepository(db)
	subjectsService := subjects.NewService(subjectsRepo)
	subjectsHandler := subjects.NewHandler(subjectsService)

	lessonsRepo := lessons.NewRepository(db)
	lessonsService := lessons.NewService(lessonsRepo)
	lessonsHandler := lessons.NewHandler(lessonsService)

	notesRepo := notes.NewRepository(db)
	notesService := notes.NewService(notesRepo)
	notesHandler := notes.NewHandler(notesService)

	progressRepo := progress.NewRepository(db)
	progressService := progress.NewService(progressRepo)
	progressHandler := progress.NewHandler(progressService)

	aiContentRepo := aicontent.NewRepository(db)
	aiContentService := aicontent.NewService(aiContentRepo)
	aiContentHandler := aicontent.NewHandler(aiContentService)

	aiRepo := ai.NewRepository(db)
	aiService := ai.NewService(aiRepo)
	aiHandler := ai.NewHandler(aiService)

	recommendationsRepo := recommendations.NewRepository(db)
	recommendationsService := recommendations.NewService(recommendationsRepo)
	recommendationsHandler := recommendations.NewHandler(recommendationsService)

	// search reuses the categories/subjects/lessons/aicontent repositories directly —
	// no separate "search" table exists, it's a fan-out query.
	searchService := search.NewService(categoriesRepo, subjectsRepo, lessonsRepo, aiContentRepo)
	searchHandler := search.NewHandler(searchService)

	// --- Health checks (unchanged) ---
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
	router.GET("/api/health", func(c *gin.Context) {
		dbStatus := "connected"
		if err := db.Ping(); err != nil {
			dbStatus = "disconnected"
		}
		c.JSON(200, gin.H{
			"status":   "ok",
			"service":  "ai-tutor-backend",
			"database": dbStatus,
		})
	})

	// --- API routes ---
	api := router.Group("/api")
	authHandler.RegisterRoutes(api, authMiddleware)
	usersHandler.RegisterRoutes(api, authMiddleware)

	categories.RegisterRoutes(api, categoriesHandler, authMiddleware)
	subjects.RegisterRoutes(api, subjectsHandler, authMiddleware)
	lessons.RegisterRoutes(api, lessonsHandler, authMiddleware)
	notes.RegisterRoutes(api, notesHandler, authMiddleware)
	progress.RegisterRoutes(api, progressHandler, authMiddleware)
	aicontent.RegisterRoutes(api, aiContentHandler, authMiddleware)
	ai.RegisterRoutes(api, aiHandler, authMiddleware)
	recommendations.RegisterRoutes(api, recommendationsHandler, authMiddleware)
	search.RegisterRoutes(api, searchHandler, authMiddleware)

	// Role-gated routes are still intentionally absent (see Day 1 notes) —
	// when an admin dashboard exists, the POST endpoints above (create
	// category/subject/lesson/note) should switch to
	// middleware.RequireAdmin() instead of the plain authMiddleware.

	addr := fmt.Sprintf(":%s", cfg.Port)
	logger.Info(fmt.Sprintf("Server starting on %s (env: %s)", addr, cfg.AppEnv))
	if err := router.Run(addr); err != nil {
		logger.Error("Server failed to start", err)
	}
}

'@
$files['migrations\000020_create_ai_tutor_tables.up.sql'] = @'
-- AI Tutor chat: a conversation belongs to a user (optionally scoped to a
-- subject), and holds an ordered list of messages (user/assistant/system).
CREATE TABLE IF NOT EXISTS ai_conversations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject_id INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_messages (
    id SERIAL PRIMARY KEY,
    conversation_id INTEGER NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    message TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_conversations_user ON ai_conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_messages_conversation ON ai_messages(conversation_id);

-- Learning recommendations: "because you completed lesson_id, we recommend
-- recommended_lesson_id". Simple, rule-based (see internal/recommendations),
-- not a machine-learning model.
CREATE TABLE IF NOT EXISTS recommendations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lesson_id INTEGER NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
    recommended_lesson_id INTEGER NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recommendations_user ON recommendations(user_id);

'@
$files['migrations\000020_create_ai_tutor_tables.down.sql'] = @'
DROP TABLE IF EXISTS recommendations;
DROP TABLE IF EXISTS ai_messages;
DROP TABLE IF EXISTS ai_conversations;

'@
$files['internal\ai\model.go'] = @'
// Package ai implements the AI Tutor chat and homework-help features using
// a rule-based (keyword-matching) educational knowledge engine — no paid
// AI API is called, per the "MVP, no paid APIs" constraint. Responses are
// predefined per topic/subject and selected by matching keywords in the
// student's question, with basic Hindi/Marathi variants for common topics.
package ai

import "time"

// Conversation mirrors an "ai_conversations" table row.
type Conversation struct {
	ID        int       `json:"id"`
	UserID    int       `json:"user_id"`
	SubjectID *int      `json:"subject_id"`
	Title     string    `json:"title"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Message mirrors an "ai_messages" table row.
type Message struct {
	ID             int       `json:"id"`
	ConversationID int       `json:"conversation_id"`
	Role           string    `json:"role"` // "user" | "assistant" | "system"
	Message        string    `json:"message"`
	CreatedAt      time.Time `json:"created_at"`
}

// ConversationWithMessages is returned by GET /api/ai/conversations/:id.
type ConversationWithMessages struct {
	Conversation
	Messages []Message `json:"messages"`
}

// ChatRequest is the expected JSON body for POST /api/ai/chat.
type ChatRequest struct {
	ConversationID *int   `json:"conversation_id"` // omit/null to start a new conversation
	SubjectID      *int   `json:"subject_id"`      // which subject this chat is scoped to
	Message        string `json:"message" binding:"required"`
	Language       string `json:"language"` // "en" (default) | "hi" | "mr"
}

// ChatResponse is returned by POST /api/ai/chat.
type ChatResponse struct {
	ConversationID int    `json:"conversation_id"`
	Reply          string `json:"reply"`
}

// HomeworkRequest is the expected JSON body for POST /api/ai/homework.
type HomeworkRequest struct {
	Question   string `json:"question" binding:"required"`
	Subject    string `json:"subject"`
	Difficulty string `json:"difficulty"`
}

// HomeworkResponse is returned by POST /api/ai/homework.
type HomeworkResponse struct {
	Explanation string   `json:"explanation"`
	StepByStep  []string `json:"step_by_step"`
	Examples    []string `json:"examples"`
	Tips        []string `json:"tips"`
}

'@
$files['internal\ai\knowledge.go'] = @'
package ai

import "strings"

// knowledgeEntry is one topic in the rule-based educational knowledge base:
// if any of Keywords appears in the student's question, its response (in
// the requested language, falling back to English) is returned.
type knowledgeEntry struct {
	Subject  string
	Keywords []string
	EN       string
	HI       string // optional — empty means "no Hindi translation yet"
	MR       string // optional — empty means "no Marathi translation yet"
}

var knowledgeBase = []knowledgeEntry{
	// --- Mathematics ---
	{
		Subject:  "Mathematics",
		Keywords: []string{"algebra"},
		EN:       "Algebra is a branch of mathematics that uses variables and symbols (like x and y) to represent numbers and relationships. You solve an equation by isolating the variable using balanced operations on both sides — for example, in x + 5 = 12, subtracting 5 from both sides gives x = 7.",
		HI:       "बीजगणित गणित की वह शाखा है जो अज्ञात संख्याओं और संबंधों को दर्शाने के लिए चर (जैसे x और y) और प्रतीकों का उपयोग करती है। समीकरण को हल करने के लिए दोनों पक्षों पर समान संक्रिया करके चर को अलग किया जाता है।",
		MR:       "बीजगणित ही गणिताची शाखा आहे जी अज्ञात संख्या आणि संबंध दर्शवण्यासाठी चल (जसे x आणि y) आणि चिन्हे वापरते. समीकरण सोडवण्यासाठी दोन्ही बाजूंवर समान क्रिया करून चल वेगळे केले जाते.",
	},
	{
		Subject:  "Mathematics",
		Keywords: []string{"geometry"},
		EN:       "Geometry is the branch of mathematics that studies shapes, sizes, angles, and space. Key ideas include perimeter (distance around a shape), area (space inside a shape), and angle types (acute, right, obtuse).",
		HI:       "ज्यामिति गणित की वह शाखा है जो आकृतियों, आकारों, कोणों और स्थान का अध्ययन करती है। मुख्य विचारों में परिमाप, क्षेत्रफल और कोणों के प्रकार शामिल हैं।",
		MR:       "भूमिती ही गणिताची शाखा आहे जी आकार, आकारमान, कोन आणि अवकाश यांचा अभ्यास करते. परिमिती, क्षेत्रफळ आणि कोनांचे प्रकार या मुख्य संकल्पना आहेत.",
	},
	{
		Subject:  "Mathematics",
		Keywords: []string{"arithmetic"},
		EN:       "Arithmetic is the most basic branch of mathematics, covering addition, subtraction, multiplication, and division of numbers.",
	},
	{
		Subject:  "Mathematics",
		Keywords: []string{"mathematics", "math"},
		EN:       "Mathematics is the study of numbers, quantities, shapes, and the relationships between them. Its main branches are arithmetic, algebra, geometry, and statistics.",
	},

	// --- Science ---
	{
		Subject:  "Science",
		Keywords: []string{"photosynthesis"},
		EN:       "Photosynthesis is the process by which plants convert sunlight, water, and carbon dioxide into glucose (energy) and oxygen. It mainly happens in the leaves, using a green pigment called chlorophyll to capture light energy.",
		HI:       "प्रकाश संश्लेषण वह प्रक्रिया है जिसके द्वारा पौधे सूर्य के प्रकाश, पानी और कार्बन डाइऑक्साइड को ग्लूकोज (ऊर्जा) और ऑक्सीजन में परिवर्तित करते हैं।",
		MR:       "प्रकाशसंश्लेषण ही प्रक्रिया आहे ज्याद्वारे झाडे सूर्यप्रकाश, पाणी आणि कार्बन डायऑक्साइडचे ग्लुकोज (ऊर्जा) आणि ऑक्सिजनमध्ये रूपांतर करतात.",
	},
	{
		Subject:  "Science",
		Keywords: []string{"physics"},
		EN:       "Physics is the natural science that studies matter, energy, motion, and the forces that govern how objects behave, through branches like mechanics, thermodynamics, and electromagnetism.",
	},
	{
		Subject:  "Science",
		Keywords: []string{"chemistry", "atom", "molecule"},
		EN:       "Chemistry studies matter: what it's made of, and how it changes. Atoms (made of protons, neutrons, and electrons) are the basic building blocks, and they bond together to form molecules.",
	},
	{
		Subject:  "Science",
		Keywords: []string{"biology", "cell"},
		EN:       "Biology is the study of living organisms, starting from the cell — the basic unit of life — up through tissues, organs, and whole organisms.",
	},

	// --- History ---
	{
		Subject:  "History",
		Keywords: []string{"ancient civilization", "mesopotamia", "indus valley"},
		EN:       "Ancient civilizations include Mesopotamia, Egypt, the Indus Valley, and Ancient China — all early societies that grew near major rivers and developed writing, law, and architecture that still influence us today.",
		HI:       "प्राचीन सभ्यताओं में मेसोपोटामिया, मिस्र, सिंधु घाटी और प्राचीन चीन शामिल हैं - ये सभी प्रारंभिक समाज बड़ी नदियों के पास विकसित हुए।",
		MR:       "प्राचीन संस्कृतींमध्ये मेसोपोटेमिया, इजिप्त, सिंधू संस्कृती आणि प्राचीन चीन यांचा समावेश होतो - या सर्व प्रारंभिक संस्कृती मोठ्या नद्यांजवळ विकसित झाल्या.",
	},
	{
		Subject:  "History",
		Keywords: []string{"roman empire", "rome"},
		EN:       "The Roman Empire built on earlier civilizations' foundations, spreading law, engineering (like aqueducts and roads), and governance across a vast territory in Europe, North Africa, and the Middle East.",
	},
	{
		Subject:  "History",
		Keywords: []string{"independence", "gandhi", "nehru", "bhagat singh"},
		EN:       "The Indian Independence Movement, led by figures like Mahatma Gandhi (nonviolent resistance), Jawaharlal Nehru, and Bhagat Singh, ended nearly 200 years of British rule on August 15, 1947.",
	},
	{
		Subject:  "History",
		Keywords: []string{"world war"},
		EN:       "World War I (1914-1918) and World War II (1939-1945) were the two deadliest conflicts in history, reshaping global politics, borders, and technology.",
	},

	// --- Programming ---
	{
		Subject:  "Programming",
		Keywords: []string{"flutter", "widget"},
		EN:       "Flutter is Google's open-source UI framework for building native apps for mobile, web, and desktop from one Dart codebase. Everything visible in a Flutter app — buttons, text, layouts — is a widget.",
	},
	{
		Subject:  "Programming",
		Keywords: []string{"golang", "go language"},
		EN:       "Go (Golang) is a simple, fast-compiling programming language from Google, popular for backend servers and APIs, with built-in support for concurrency via goroutines.",
	},
	{
		Subject:  "Programming",
		Keywords: []string{"variable"},
		EN:       "A variable is a named storage location that holds a value your program can read or change — for example, in Dart, 'int score = 10;' creates a variable named score holding the number 10.",
	},
	{
		Subject:  "Programming",
		Keywords: []string{"function"},
		EN:       "A function is a reusable block of code that performs a specific task, optionally taking inputs (parameters) and returning a result.",
	},

	// --- English ---
	{
		Subject:  "English",
		Keywords: []string{"grammar"},
		EN:       "Grammar is the set of rules governing how words combine into sentences — covering parts of speech (nouns, verbs, adjectives), sentence structure, and tenses.",
	},
	{
		Subject:  "English",
		Keywords: []string{"vocabulary"},
		EN:       "Vocabulary is the set of words you know and understand. Building it through reading and context clues helps you express ideas more precisely.",
	},
	{
		Subject:  "English",
		Keywords: []string{"writing", "essay", "paragraph"},
		EN:       "Good writing follows a process: plan your main idea, draft freely, then revise for clarity and edit for grammar. A strong paragraph opens with a topic sentence, gives supporting details, and closes with a concluding thought.",
	},
}

// genericFallback is used when no keyword matches — translated per language
// so the response is never in the wrong language even when the topic is unknown.
var genericFallback = map[string]string{
	"en": "That's a great question! I don't have a specific answer for that topic yet, but I can help with Mathematics (algebra, geometry), Science (physics, chemistry, biology), History (ancient civilizations, independence movement), Programming (Flutter, Go), and English (grammar, vocabulary, writing). Try asking about one of those!",
	"hi": "यह एक बहुत अच्छा प्रश्न है! मेरे पास अभी इस विषय के लिए कोई विशेष उत्तर नहीं है, लेकिन मैं गणित, विज्ञान, इतिहास, प्रोग्रामिंग और अंग्रेजी में मदद कर सकता हूं।",
	"mr": "हा एक चांगला प्रश्न आहे! माझ्याकडे या विषयासाठी सध्या विशिष्ट उत्तर नाही, पण मी गणित, विज्ञान, इतिहास, प्रोग्रामिंग आणि इंग्रजीमध्ये मदत करू शकतो.",
}

// FindAnswer scans the knowledge base for a keyword match against the
// question (case-insensitive substring match) and returns the response in
// the requested language. If the entry has no translation for that
// language, it falls back to English. If nothing matches at all, it
// returns a translated generic fallback message.
func FindAnswer(question, language string) string {
	q := strings.ToLower(question)
	lang := normalizeLanguage(language)

	for _, entry := range knowledgeBase {
		for _, kw := range entry.Keywords {
			if strings.Contains(q, kw) {
				return pickTranslation(entry, lang)
			}
		}
	}

	if msg, ok := genericFallback[lang]; ok {
		return msg
	}
	return genericFallback["en"]
}

func pickTranslation(entry knowledgeEntry, lang string) string {
	switch lang {
	case "hi":
		if entry.HI != "" {
			return entry.HI
		}
	case "mr":
		if entry.MR != "" {
			return entry.MR
		}
	}
	return entry.EN
}

func normalizeLanguage(lang string) string {
	switch strings.ToLower(strings.TrimSpace(lang)) {
	case "hi", "hindi":
		return "hi"
	case "mr", "marathi":
		return "mr"
	default:
		return "en"
	}
}

'@
$files['internal\ai\homework.go'] = @'
package ai

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// linearEquationPattern matches simple linear equations of the form
// "2x + 6 = 10" or "3x - 4 = 11" (a single variable, one +/- term, one
// equals sign). It's intentionally simple — this is a rule-based MVP
// homework helper, not a full computer-algebra system.
var linearEquationPattern = regexp.MustCompile(`(?i)^\s*(-?\d*)\s*([a-z])\s*([+-])\s*(\d+)\s*=\s*(-?\d+)\s*$`)

// trySolveLinearEquation attempts to solve "ax + b = c" / "ax - b = c" for
// x, returning a step-by-step explanation if the question matches the
// pattern, or ok=false if it doesn't (so the caller can fall back to the
// general knowledge base).
func trySolveLinearEquation(question string) (steps []string, ok bool) {
	match := linearEquationPattern.FindStringSubmatch(strings.TrimSpace(question))
	if match == nil {
		return nil, false
	}

	coeffStr, variable, sign, bStr, cStr := match[1], match[2], match[3], match[4], match[5]

	a := 1
	if coeffStr != "" && coeffStr != "-" {
		parsed, err := strconv.Atoi(coeffStr)
		if err != nil {
			return nil, false
		}
		a = parsed
	} else if coeffStr == "-" {
		a = -1
	}

	b, err := strconv.Atoi(bStr)
	if err != nil {
		return nil, false
	}
	c, err := strconv.Atoi(cStr)
	if err != nil {
		return nil, false
	}
	if a == 0 {
		return nil, false
	}

	// ax + b = c  =>  ax = c - b
	// ax - b = c  =>  ax = c + b
	var rhsAfterMove int
	var step1 string
	if sign == "+" {
		rhsAfterMove = c - b
		step1 = fmt.Sprintf("Subtract %d from both sides: %d%s = %d", b, a, variable, rhsAfterMove)
	} else {
		rhsAfterMove = c + b
		step1 = fmt.Sprintf("Add %d to both sides: %d%s = %d", b, a, variable, rhsAfterMove)
	}

	if rhsAfterMove%a != 0 {
		// Non-integer answer — still show the division step with a decimal.
		result := float64(rhsAfterMove) / float64(a)
		step2 := fmt.Sprintf("Divide both sides by %d: %s = %.2f", a, variable, result)
		return []string{step1, step2}, true
	}

	result := rhsAfterMove / a
	step2 := fmt.Sprintf("Divide both sides by %d: %s = %d", a, variable, result)
	return []string{step1, step2}, true
}

// SolveHomework builds a HomeworkResponse for a student's question. It
// first tries the linear-equation solver (for math-equation-shaped
// questions), then falls back to the same keyword knowledge base used by
// chat, reshaped into explanation/steps/examples/tips.
func SolveHomework(req HomeworkRequest) HomeworkResponse {
	if steps, ok := trySolveLinearEquation(req.Question); ok {
		return HomeworkResponse{
			Explanation: "This is a linear equation — solve it by isolating the variable using the same operation on both sides.",
			StepByStep:  steps,
			Examples:    []string{"x + 5 = 12  ->  x = 7", "3x = 21  ->  x = 7"},
			Tips:        []string{"Whatever you do to one side of the equation, do to the other side too.", "Check your answer by substituting it back into the original equation."},
		}
	}

	explanation := FindAnswer(req.Question, "en")
	return HomeworkResponse{
		Explanation: explanation,
		StepByStep:  []string{"Read the question carefully and identify what topic it's about.", "Review the explanation above for the relevant concept.", "Try applying it to your specific problem step by step."},
		Examples:    []string{},
		Tips:        []string{"Break the problem into smaller parts.", "If you're stuck, try the AI Tutor chat for a follow-up question."},
	}
}

'@
$files['internal\ai\repository.go'] = @'
package ai

import (
	"database/sql"
	"errors"
)

// ErrConversationNotFound is returned when a conversation doesn't exist
// or doesn't belong to the requesting user.
var ErrConversationNotFound = errors.New("conversation not found")

// Repository handles direct SQL access for ai_conversations/ai_messages.
type Repository struct {
	db *sql.DB
}

// NewRepository builds an ai Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// CreateConversation inserts a new conversation and returns its ID.
func (r *Repository) CreateConversation(userID int, subjectID *int, title string) (int, error) {
	var id int
	query := `INSERT INTO ai_conversations (user_id, subject_id, title) VALUES ($1, $2, $3) RETURNING id`
	err := r.db.QueryRow(query, userID, subjectID, title).Scan(&id)
	return id, err
}

// TouchConversation updates a conversation's updated_at to now (called
// whenever a new message is added).
func (r *Repository) TouchConversation(conversationID int) error {
	_, err := r.db.Exec(`UPDATE ai_conversations SET updated_at = NOW() WHERE id = $1`, conversationID)
	return err
}

// FindConversationByID returns a conversation, scoped to userID so users
// can't access each other's conversations.
func (r *Repository) FindConversationByID(userID, conversationID int) (*Conversation, error) {
	query := `SELECT id, user_id, subject_id, title, created_at, updated_at FROM ai_conversations WHERE id = $1 AND user_id = $2`
	var c Conversation
	var subjectID sql.NullInt64
	err := r.db.QueryRow(query, conversationID, userID).Scan(&c.ID, &c.UserID, &subjectID, &c.Title, &c.CreatedAt, &c.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrConversationNotFound
	}
	if err != nil {
		return nil, err
	}
	if subjectID.Valid {
		v := int(subjectID.Int64)
		c.SubjectID = &v
	}
	return &c, nil
}

// ListConversations returns every conversation for a user, most recently
// updated first.
func (r *Repository) ListConversations(userID int) ([]Conversation, error) {
	query := `SELECT id, user_id, subject_id, title, created_at, updated_at FROM ai_conversations WHERE user_id = $1 ORDER BY updated_at DESC`
	rows, err := r.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Conversation
	for rows.Next() {
		var c Conversation
		var subjectID sql.NullInt64
		if err := rows.Scan(&c.ID, &c.UserID, &subjectID, &c.Title, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		if subjectID.Valid {
			v := int(subjectID.Int64)
			c.SubjectID = &v
		}
		result = append(result, c)
	}
	return result, nil
}

// DeleteConversation removes a conversation (and its messages, via
// ON DELETE CASCADE), scoped to userID.
func (r *Repository) DeleteConversation(userID, conversationID int) error {
	_, err := r.db.Exec(`DELETE FROM ai_conversations WHERE id = $1 AND user_id = $2`, conversationID, userID)
	return err
}

// AddMessage inserts a message into a conversation.
func (r *Repository) AddMessage(conversationID int, role, message string) (int, error) {
	var id int
	query := `INSERT INTO ai_messages (conversation_id, role, message) VALUES ($1, $2, $3) RETURNING id`
	err := r.db.QueryRow(query, conversationID, role, message).Scan(&id)
	return id, err
}

// ListMessages returns every message in a conversation, oldest first.
func (r *Repository) ListMessages(conversationID int) ([]Message, error) {
	query := `SELECT id, conversation_id, role, message, created_at FROM ai_messages WHERE conversation_id = $1 ORDER BY id`
	rows, err := r.db.Query(query, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Message
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.ConversationID, &m.Role, &m.Message, &m.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, m)
	}
	return result, nil
}

'@
$files['internal\ai\service.go'] = @'
package ai

import "strings"

// Service contains the business logic for AI Tutor chat and homework help.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into an ai Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// Chat handles one turn of a conversation: creates a new conversation if
// none was given, saves the student's message, generates a rule-based
// reply (via the knowledge base, in the requested language), saves the
// reply, and returns it.
func (s *Service) Chat(userID int, req ChatRequest) (*ChatResponse, error) {
	conversationID := 0

	if req.ConversationID != nil {
		// Verify the conversation exists and belongs to this user.
		conv, err := s.repo.FindConversationByID(userID, *req.ConversationID)
		if err != nil {
			return nil, err
		}
		conversationID = conv.ID
	} else {
		title := req.Message
		if len(title) > 50 {
			title = title[:50] + "..."
		}
		id, err := s.repo.CreateConversation(userID, req.SubjectID, title)
		if err != nil {
			return nil, err
		}
		conversationID = id
	}

	if _, err := s.repo.AddMessage(conversationID, "user", req.Message); err != nil {
		return nil, err
	}

	reply := FindAnswer(req.Message, req.Language)

	if _, err := s.repo.AddMessage(conversationID, "assistant", reply); err != nil {
		return nil, err
	}
	if err := s.repo.TouchConversation(conversationID); err != nil {
		return nil, err
	}

	return &ChatResponse{ConversationID: conversationID, Reply: reply}, nil
}

// ListConversations returns a user's conversation history.
func (s *Service) ListConversations(userID int) ([]Conversation, error) {
	return s.repo.ListConversations(userID)
}

// GetConversation returns a conversation with all of its messages.
func (s *Service) GetConversation(userID, conversationID int) (*ConversationWithMessages, error) {
	conv, err := s.repo.FindConversationByID(userID, conversationID)
	if err != nil {
		return nil, err
	}
	messages, err := s.repo.ListMessages(conversationID)
	if err != nil {
		return nil, err
	}
	return &ConversationWithMessages{Conversation: *conv, Messages: messages}, nil
}

// DeleteConversation removes a conversation.
func (s *Service) DeleteConversation(userID, conversationID int) error {
	return s.repo.DeleteConversation(userID, conversationID)
}

// Homework generates a structured homework-help response.
func (s *Service) Homework(req HomeworkRequest) HomeworkResponse {
	// Subject is currently just contextual metadata for future use (e.g.
	// biasing which knowledge-base entries to prefer) — the MVP knowledge
	// base already scopes by keyword, so it isn't strictly required yet.
	_ = strings.TrimSpace(req.Subject)
	return SolveHomework(req)
}

'@
$files['internal\ai\handler.go'] = @'
package ai

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the ai Service.
type Handler struct {
	service *Service
}

// NewHandler builds an ai Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// Chat handles POST /api/ai/chat.
func (h *Handler) Chat(c *gin.Context) {
	var req ChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A message is required")
		return
	}

	userID := c.GetInt("user_id")

	resp, err := h.service.Chat(userID, req)
	if err != nil {
		if errors.Is(err, ErrConversationNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Conversation not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to process chat message")
		return
	}

	utils.RespondSuccess(c, http.StatusOK, "Reply generated", resp)
}

// ListConversations handles GET /api/ai/conversations.
func (h *Handler) ListConversations(c *gin.Context) {
	userID := c.GetInt("user_id")

	list, err := h.service.ListConversations(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load conversations")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Conversations fetched", list)
}

// GetConversation handles GET /api/ai/conversations/:id.
func (h *Handler) GetConversation(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid conversation id")
		return
	}

	userID := c.GetInt("user_id")

	conv, err := h.service.GetConversation(userID, id)
	if err != nil {
		if errors.Is(err, ErrConversationNotFound) {
			utils.RespondError(c, http.StatusNotFound, "Conversation not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load conversation")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Conversation fetched", conv)
}

// DeleteConversation handles DELETE /api/ai/conversations/:id.
func (h *Handler) DeleteConversation(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "Invalid conversation id")
		return
	}

	userID := c.GetInt("user_id")

	if err := h.service.DeleteConversation(userID, id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to delete conversation")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Conversation deleted", nil)
}

// Homework handles POST /api/ai/homework.
func (h *Handler) Homework(c *gin.Context) {
	var req HomeworkRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "A question is required")
		return
	}

	resp := h.service.Homework(req)
	utils.RespondSuccess(c, http.StatusOK, "Homework help generated", resp)
}

'@
$files['internal\ai\routes.go'] = @'
package ai

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches all /api/ai/* routes. All require auth since
// chat history and recommendations are always scoped to the current user.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	group := router.Group("/ai")
	group.Use(authMiddleware)
	{
		group.POST("/chat", handler.Chat)
		group.GET("/conversations", handler.ListConversations)
		group.GET("/conversations/:id", handler.GetConversation)
		group.DELETE("/conversations/:id", handler.DeleteConversation)
		group.POST("/homework", handler.Homework)
	}
}

'@
$files['internal\recommendations\model.go'] = @'
// Package recommendations implements simple, rule-based "what to learn
// next" suggestions — NOT a machine-learning model. The rule is: for each
// subject where the student has completed lessons, recommend the next
// not-yet-completed lesson in that subject (by order_number). This mirrors
// the spec's examples (completed Mathematics Introduction + Algebra ->
// recommend Geometry) using the existing lessons.order_number column
// instead of a hardcoded lesson-to-lesson map.
package recommendations

import "time"

// Recommendation mirrors a "recommendations" table row, with the
// recommended lesson's title/subject joined in for direct display.
type Recommendation struct {
	ID                   int       `json:"id"`
	UserID               int       `json:"user_id"`
	LessonID             int       `json:"lesson_id"`
	RecommendedLessonID  int       `json:"recommended_lesson_id"`
	RecommendedTitle     string    `json:"recommended_title"`
	RecommendedSubjectID int       `json:"recommended_subject_id"`
	SubjectName          string    `json:"subject_name"`
	CreatedAt            time.Time `json:"created_at"`
}

'@
$files['internal\recommendations\repository.go'] = @'
package recommendations

import "database/sql"

// Repository handles direct SQL access for recommendations, plus the
// underlying query that computes the "next not-yet-completed lesson per
// subject" rule described in model.go.
type Repository struct {
	db *sql.DB
}

// NewRepository builds a recommendations Repository around an existing *sql.DB.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// ComputeAndStore recomputes this user's recommendations from their
// current progress and (re)persists them to the "recommendations" table,
// then returns the fresh list. Called on every GET so recommendations
// always reflect the latest completed lessons — simpler than trying to
// incrementally maintain the table.
func (r *Repository) ComputeAndStore(userID int) ([]Recommendation, error) {
	// For every subject where the user has completed at least one lesson,
	// find the lowest order_number lesson in that subject that they have
	// NOT completed yet — that's the "next" recommendation. The most
	// recently completed lesson in that subject becomes the "lesson_id"
	// (why this was recommended).
	query := `
		WITH completed AS (
			SELECT l.subject_id, l.id AS lesson_id, l.order_number, lp.completed_at
			FROM lesson_progress lp
			JOIN lessons l ON l.id = lp.lesson_id
			WHERE lp.user_id = $1
		),
		latest_completed_per_subject AS (
			SELECT subject_id, lesson_id, order_number,
			       ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY completed_at DESC) AS rn
			FROM completed
		),
		next_lesson AS (
			SELECT lc.subject_id, lc.lesson_id AS source_lesson_id,
			       (
			           SELECT l2.id FROM lessons l2
			           WHERE l2.subject_id = lc.subject_id
			             AND l2.id NOT IN (SELECT lesson_id FROM completed WHERE subject_id = lc.subject_id)
			           ORDER BY l2.order_number ASC
			           LIMIT 1
			       ) AS recommended_lesson_id
			FROM latest_completed_per_subject lc
			WHERE lc.rn = 1
		)
		SELECT source_lesson_id, recommended_lesson_id, subject_id
		FROM next_lesson
		WHERE recommended_lesson_id IS NOT NULL
	`

	rows, err := r.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	type pair struct {
		sourceLessonID      int
		recommendedLessonID int
		subjectID           int
	}
	var pairs []pair
	for rows.Next() {
		var p pair
		if err := rows.Scan(&p.sourceLessonID, &p.recommendedLessonID, &p.subjectID); err != nil {
			rows.Close()
			return nil, err
		}
		pairs = append(pairs, p)
	}
	rows.Close()

	// Persist: clear old recommendations for this user, insert the fresh set.
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	if _, err := tx.Exec(`DELETE FROM recommendations WHERE user_id = $1`, userID); err != nil {
		tx.Rollback()
		return nil, err
	}
	for _, p := range pairs {
		if _, err := tx.Exec(
			`INSERT INTO recommendations (user_id, lesson_id, recommended_lesson_id) VALUES ($1, $2, $3)`,
			userID, p.sourceLessonID, p.recommendedLessonID,
		); err != nil {
			tx.Rollback()
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return r.ListByUser(userID)
}

// ListByUser returns a user's stored recommendations, joined with the
// recommended lesson's title and subject for direct display.
func (r *Repository) ListByUser(userID int) ([]Recommendation, error) {
	query := `
		SELECT r.id, r.user_id, r.lesson_id, r.recommended_lesson_id, r.created_at,
		       l.title, l.subject_id, s.name
		FROM recommendations r
		JOIN lessons l ON l.id = r.recommended_lesson_id
		JOIN subjects s ON s.id = l.subject_id
		WHERE r.user_id = $1
		ORDER BY r.created_at DESC
	`
	rows, err := r.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []Recommendation
	for rows.Next() {
		var rec Recommendation
		if err := rows.Scan(
			&rec.ID, &rec.UserID, &rec.LessonID, &rec.RecommendedLessonID, &rec.CreatedAt,
			&rec.RecommendedTitle, &rec.RecommendedSubjectID, &rec.SubjectName,
		); err != nil {
			return nil, err
		}
		result = append(result, rec)
	}
	return result, nil
}

'@
$files['internal\recommendations\service.go'] = @'
package recommendations

// Service contains the business logic for recommendations.
type Service struct {
	repo *Repository
}

// NewService wires a Repository into a recommendations Service.
func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// GetForUser recomputes and returns a user's current recommendations.
func (s *Service) GetForUser(userID int) ([]Recommendation, error) {
	return s.repo.ComputeAndStore(userID)
}

'@
$files['internal\recommendations\handler.go'] = @'
package recommendations

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"ai-tutor-backend/utils"
)

// Handler adapts HTTP requests/responses to the recommendations Service.
type Handler struct {
	service *Service
}

// NewHandler builds a recommendations Handler around a Service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// GetRecommendations handles GET /api/ai/recommendations.
func (h *Handler) GetRecommendations(c *gin.Context) {
	userID := c.GetInt("user_id")

	list, err := h.service.GetForUser(userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "Failed to load recommendations")
		return
	}
	utils.RespondSuccess(c, http.StatusOK, "Recommendations fetched", list)
}

'@
$files['internal\recommendations\routes.go'] = @'
package recommendations

import "github.com/gin-gonic/gin"

// RegisterRoutes attaches GET /api/ai/recommendations.
func RegisterRoutes(router *gin.RouterGroup, handler *Handler, authMiddleware gin.HandlerFunc) {
	router.GET("/ai/recommendations", authMiddleware, handler.GetRecommendations)
}

'@

foreach ($path in $files.Keys) {
    $fullPath = Join-Path $PWD $path
    $dir = Split-Path $fullPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($fullPath, $files[$path], [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated: $path"
}
Write-Host "Backend AI Tutor (Day 3) files applied."
