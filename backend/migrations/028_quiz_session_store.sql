-- Migration: Server-side answer-key store for AI-generated freeform quizzes.
--
-- Fixes CRITICAL security issue found in the bug audit (20 July 2026):
-- freeform quiz answers were graded against a CLIENT-SUPPLIED answer key
-- (the /generate response included correct_option/correct_options/
-- correct_text, and /freeform/attempt just trusted whatever the client
-- echoed back) - so any tampered client could score 100% and farm XP,
-- badges, and certificates.
--
-- Generated questions (with their real answer key) are now persisted here
-- at /api/quiz/generate time, keyed by an unguessable session id. Grading
-- at /api/quiz/freeform/attempt reads the key back from this table -
-- never from the request body.

BEGIN;

CREATE TABLE IF NOT EXISTS quiz_generated_sessions (
    id             TEXT PRIMARY KEY,
    user_id        BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    topic          TEXT NOT NULL,
    subject_id     BIGINT,
    questions_json JSONB NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at     TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_quiz_generated_sessions_user_id ON quiz_generated_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_quiz_generated_sessions_expires_at ON quiz_generated_sessions(expires_at);

-- Optional: a periodic job (cron / pg_cron) can run this to sweep expired
-- sessions instead of letting the table grow unbounded:
--   DELETE FROM quiz_generated_sessions WHERE expires_at < now();

COMMIT;
