-- Recreates "lessons" with the Day 2 schema (subject_id, pdf_url, order_number)
-- replacing the Day 1 placeholder that was dropped in migration 000005.
CREATE TABLE IF NOT EXISTS lessons (
    id SERIAL PRIMARY KEY,
    subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    video_url TEXT,
    pdf_url TEXT,
    duration INTEGER,
    order_number INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lessons_subject_id ON lessons(subject_id);