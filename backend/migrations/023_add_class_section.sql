-- Class/Section: student-only fields, assigned exclusively by admin, used
-- only for Leaderboard filtering. Nullable so every existing user
-- (student or otherwise) stays exactly as-is until an admin sets these.

BEGIN;

ALTER TABLE users ADD COLUMN IF NOT EXISTS class VARCHAR(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS section VARCHAR(10);

CREATE INDEX IF NOT EXISTS idx_users_class_section ON users(class, section);

COMMIT;
