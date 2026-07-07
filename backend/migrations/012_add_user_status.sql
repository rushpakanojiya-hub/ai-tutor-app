-- Adds account status so teacher applications can sit as "pending" until
-- an admin approves them, without touching existing student accounts
-- (which all default to 'active', so nothing about student login changes).

BEGIN;

ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'active';

-- Backfill: every existing account (all students so far) is active.
UPDATE users SET status = 'active' WHERE status IS NULL;

-- Teacher-specific application details. Resume/certificate file URLs are
-- deliberately left out for now - that needs a file storage service
-- (e.g. Cloudinary) to be set up before file upload can be added safely.
CREATE TABLE IF NOT EXISTS teacher_profiles (
    id             SERIAL PRIMARY KEY,
    user_id        INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    phone          VARCHAR(30),
    qualification  VARCHAR(255),
    experience     VARCHAR(255),
    subjects       TEXT,
    bio            TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
