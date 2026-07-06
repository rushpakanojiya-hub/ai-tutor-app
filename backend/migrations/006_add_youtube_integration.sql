-- Migration: Add YouTube video integration
-- Safe to run on existing DB. Does NOT touch auth, categories, subjects, notes,
-- search, progress-tracking, or ai_tutor tables.

BEGIN;

-- 1. Extend lessons table
ALTER TABLE lessons
    ADD COLUMN IF NOT EXISTS youtube_search_query TEXT,
    ADD COLUMN IF NOT EXISTS youtube_enabled BOOLEAN DEFAULT true;

-- 2. Cache table (24h TTL, keyed by lesson_id + query)
CREATE TABLE IF NOT EXISTS youtube_cache (
    id            BIGSERIAL PRIMARY KEY,
    lesson_id     BIGINT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
    query         TEXT NOT NULL,
    response_json JSONB NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_youtube_cache_lesson_id ON youtube_cache(lesson_id);
CREATE INDEX IF NOT EXISTS idx_youtube_cache_expires_at ON youtube_cache(expires_at);

-- 3. Per-user, per-video watch progress
CREATE TABLE IF NOT EXISTS lesson_video_progress (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lesson_id       BIGINT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
    video_id        TEXT NOT NULL,
    watched_seconds INTEGER NOT NULL DEFAULT 0,
    completed       BOOLEAN NOT NULL DEFAULT false,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, lesson_id, video_id)
);

CREATE INDEX IF NOT EXISTS idx_lesson_video_progress_user_lesson
    ON lesson_video_progress(user_id, lesson_id);

COMMIT;
