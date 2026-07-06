-- Quiz & Assessment module, scoped realistically to what this app can
-- actually support today: persisted quiz attempts (lesson-based AND
-- freeform AI-generated), per-question answer review, and analytics
-- computed from real attempt data. Does NOT include assignments,
-- leaderboards, certificates, or teacher/admin quiz authoring - those are
-- separate, much larger features.

BEGIN;

CREATE TABLE IF NOT EXISTS quiz_attempts (
    id                  SERIAL PRIMARY KEY,
    user_id             INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lesson_id           INTEGER REFERENCES lessons(id) ON DELETE CASCADE,
    subject_id          INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
    topic               VARCHAR(255),
    total_questions     INTEGER NOT NULL,
    correct_count       INTEGER NOT NULL,
    score_percent       INTEGER NOT NULL,
    time_taken_seconds  INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quiz_attempt_answers (
    id               SERIAL PRIMARY KEY,
    attempt_id       INTEGER NOT NULL REFERENCES quiz_attempts(id) ON DELETE CASCADE,
    question_index   INTEGER NOT NULL,
    question_text    TEXT NOT NULL,
    options          JSONB NOT NULL,
    selected_option  INTEGER, -- NULL means skipped
    correct_option   INTEGER NOT NULL,
    is_correct       BOOLEAN NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_quiz_attempts_user ON quiz_attempts(user_id);
CREATE INDEX IF NOT EXISTS idx_quiz_attempts_subject ON quiz_attempts(subject_id);
CREATE INDEX IF NOT EXISTS idx_quiz_attempts_lesson ON quiz_attempts(lesson_id);
CREATE INDEX IF NOT EXISTS idx_quiz_attempt_answers_attempt ON quiz_attempt_answers(attempt_id);

COMMIT;
