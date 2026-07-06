-- Extends quiz attempts to support multiple question types (beyond
-- single-correct MCQ), scoped to the AI Quiz Generator (freeform) path.
-- Lesson-based quizzes are untouched - they keep using correct_option
-- exactly as before.

BEGIN;

ALTER TABLE quiz_attempt_answers
    ADD COLUMN IF NOT EXISTS question_type VARCHAR(30) NOT NULL DEFAULT 'single_mcq',
    ADD COLUMN IF NOT EXISTS correct_options JSONB,        -- for multiple_mcq: array of correct indices
    ADD COLUMN IF NOT EXISTS selected_options JSONB,       -- for multiple_mcq: array of selected indices
    ADD COLUMN IF NOT EXISTS correct_text TEXT,            -- for fill_blank / short_answer: accepted answer
    ADD COLUMN IF NOT EXISTS submitted_text TEXT,          -- for fill_blank / short_answer: student's answer
    ADD COLUMN IF NOT EXISTS hint TEXT,
    ADD COLUMN IF NOT EXISTS explanation TEXT,
    ADD COLUMN IF NOT EXISTS difficulty_score INTEGER;     -- 1-10, set by the AI generator

-- Options is only meaningful for MCQ-style types; relax NOT NULL so
-- fill_blank/short_answer rows (which have no options list) can insert '[]'.
ALTER TABLE quiz_attempt_answers ALTER COLUMN options SET DEFAULT '[]';

COMMIT;
