package ai

import "fmt"

// maxContextMessages caps how many recent messages are loaded from history
// and sent to Groq on each turn - per spec: "Load last 10 messages, then
// append current message, then send to Groq".
const maxContextMessages = 10

// buildSystemPrompt constructs the instruction Groq receives before any
// conversation history. This is what makes the AI Tutor subject-aware and
// language-aware, entirely replacing the old rule-based keyword matching.
func buildSystemPrompt(subjectName, language string) string {
	prompt := `You are an advanced AI Tutor.

You help students learn.

You can teach:
- Mathematics
- Science
- Physics
- Chemistry
- Biology
- History
- Geography
- English
- Programming
- Computer Science

Your responses must:
- be educational
- be beginner friendly
- explain concepts clearly
- provide examples
- provide step-by-step solutions
- support follow-up questions`

	if subjectName != "" {
		prompt += fmt.Sprintf("\n\nCurrent subject:\n%s", subjectName)
	}

	switch language {
	case "hi":
		prompt += "\n\nRespond in Hindi."
	case "mr":
		prompt += "\n\nRespond in Marathi."
	}

	return prompt
}

// buildMessages assembles the exact message list sent to Groq: the system
// prompt, then the session's recent history (oldest first), then the
// student's current message. This is where "context memory" happens - the
// LLM sees the whole recent conversation and resolves references like
// "its types" itself.
func buildMessages(subjectName, language string, history []ChatMessage, currentMessage string) []ChatCompletionMessage {
	messages := []ChatCompletionMessage{{Role: "system", Content: buildSystemPrompt(subjectName, language)}}

	for _, m := range history {
		messages = append(messages, ChatCompletionMessage{Role: m.Role, Content: m.Message})
	}

	messages = append(messages, ChatCompletionMessage{Role: "user", Content: currentMessage})

	return messages
}
