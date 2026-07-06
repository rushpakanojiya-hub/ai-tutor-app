-- Stores AI-generated educational content per lesson: explanation, summary,
-- key points, worked examples, practice questions, and a quiz. This is what
-- LessonPlayerScreen renders instead of (or alongside) a video, replacing
-- the old cartoon/placeholder video approach.
CREATE TABLE IF NOT EXISTS lesson_ai_content (
    id SERIAL PRIMARY KEY,
    lesson_id INTEGER NOT NULL UNIQUE REFERENCES lessons(id) ON DELETE CASCADE,
    explanation TEXT NOT NULL,
    summary TEXT NOT NULL,
    key_points JSONB NOT NULL DEFAULT '[]',
    examples JSONB NOT NULL DEFAULT '[]',
    practice_questions JSONB NOT NULL DEFAULT '[]',
    quiz_json JSONB NOT NULL DEFAULT '[]',
    generated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
