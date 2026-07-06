-- Tracks which calendar days a user was active (completed a lesson,
-- attempted a quiz, or used AI Tutor), so "Learning Streak" on the
-- dashboard reflects real behavior instead of a fabricated number.

BEGIN;

CREATE TABLE IF NOT EXISTS user_activity_days (
    id            SERIAL PRIMARY KEY,
    user_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_date DATE NOT NULL,
    UNIQUE (user_id, activity_date)
);

CREATE INDEX IF NOT EXISTS idx_user_activity_days_user ON user_activity_days(user_id, activity_date DESC);

COMMIT;
