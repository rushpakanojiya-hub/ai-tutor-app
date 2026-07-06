package ai

import "strings"

// knowledgeEntry is one topic in the rule-based educational knowledge base:
// if any of Keywords appears in the student's question, its response (in
// the requested language, falling back to English) is returned.
type knowledgeEntry struct {
	Subject  string
	Keywords []string
	EN       string
	HI       string // optional - empty means "no Hindi translation yet"
	MR       string // optional - empty means "no Marathi translation yet"
}

var knowledgeBase = []knowledgeEntry{
	// --- Mathematics ---
	{
		Subject:  "Mathematics",
		Keywords: []string{"algebra"},
		EN:       "Algebra is a branch of mathematics that uses variables and symbols (like x and y) to represent numbers and relationships. You solve an equation by isolating the variable using balanced operations on both sides - for example, in x + 5 = 12, subtracting 5 from both sides gives x = 7.",
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
		EN:       "Biology is the study of living organisms, starting from the cell - the basic unit of life - up through tissues, organs, and whole organisms.",
	},

	// --- History ---
	{
		Subject:  "History",
		Keywords: []string{"ancient civilization", "mesopotamia", "indus valley"},
		EN:       "Ancient civilizations include Mesopotamia, Egypt, the Indus Valley, and Ancient China - all early societies that grew near major rivers and developed writing, law, and architecture that still influence us today.",
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
		EN:       "Flutter is Google's open-source UI framework for building native apps for mobile, web, and desktop from one Dart codebase. Everything visible in a Flutter app - buttons, text, layouts - is a widget.",
	},
	{
		Subject:  "Programming",
		Keywords: []string{"golang", "go language"},
		EN:       "Go (Golang) is a simple, fast-compiling programming language from Google, popular for backend servers and APIs, with built-in support for concurrency via goroutines.",
	},
	{
		Subject:  "Programming",
		Keywords: []string{"variable"},
		EN:       "A variable is a named storage location that holds a value your program can read or change - for example, in Dart, 'int score = 10;' creates a variable named score holding the number 10.",
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
		EN:       "Grammar is the set of rules governing how words combine into sentences - covering parts of speech (nouns, verbs, adjectives), sentence structure, and tenses.",
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

// genericFallback is used when no keyword matches - translated per language
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

// isGenericFallback reports whether reply is exactly the "I don't have a
// specific answer" fallback message (in any supported language) — used by
// the chat context-fallback heuristic in service.go to detect "no match"
// without re-running the keyword search.
func isGenericFallback(reply, language string) bool {
	lang := normalizeLanguage(language)
	return reply == genericFallback[lang]
}