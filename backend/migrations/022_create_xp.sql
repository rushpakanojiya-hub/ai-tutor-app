-- XP/Points: an append-only ledger (for idempotent awarding - e.g. course
-- completion or a daily-study bonus should never be double-counted) plus
-- a running-totals table for fast dashboard reads.

BEGIN;

CREATE TABLE IF NOT EXISTS xp_events (
    id SERIAL PRIMARY KEY,
    student_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_type VARCHAR(30) NOT NULL, -- quiz_completion | homework_submission | course_completion | daily_study | study_streak
    reference_key VARCHAR(100) NOT NULL, -- e.g. 'quiz-attempt-123', 'course-5', 'daily-2026-07-09', 'streak-milestone-1'
    xp_amount INTEGER NOT NULL,
    points_amount INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(student_id, activity_type, reference_key)
);

CREATE TABLE IF NOT EXISTS student_xp_totals (
    student_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    total_xp INTEGER NOT NULL DEFAULT 0,
    total_points INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_xp_events_student ON xp_events(student_id);

COMMIT;
