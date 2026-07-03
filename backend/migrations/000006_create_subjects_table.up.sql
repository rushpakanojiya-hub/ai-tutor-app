CREATE TABLE IF NOT EXISTS subjects (
    id SERIAL PRIMARY KEY,
    category_id INTEGER NOT NULL REFERENCES course_categories(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    thumbnail TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subjects_category_id ON subjects(category_id);