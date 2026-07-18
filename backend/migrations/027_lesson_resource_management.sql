-- Lesson Resource Management: lessons need a publish/draft lifecycle
-- (same pattern as subjects.status from migration 025), a way to tell
-- an uploaded video apart from a pasted YouTube URL, and a title/
-- description for the PDF notes attached to a lesson.
-- Safe to run on existing DB. Does NOT touch auth, categories, subjects,
-- notes, search, progress-tracking, or ai_tutor tables.

BEGIN;

ALTER TABLE lessons
    ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'draft',
    ADD COLUMN IF NOT EXISTS video_source VARCHAR(20) NOT NULL DEFAULT 'upload',
    ADD COLUMN IF NOT EXISTS pdf_title TEXT,
    ADD COLUMN IF NOT EXISTS pdf_description TEXT;

CREATE INDEX IF NOT EXISTS idx_lessons_status ON lessons(status);

COMMIT;