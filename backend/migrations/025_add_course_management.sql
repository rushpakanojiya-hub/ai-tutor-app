-- Course Management: subjects need a published/draft status (didn't
-- exist before - Create() always just... existed with no lifecycle).
-- Lessons get a dedicated assignment-document slot, separate from
-- pdf_url (lesson notes) and video_url (lesson video) - this is the
-- "Upload Assignments" admin feature, not the interactive Assignment
-- module which already has its own model.

BEGIN;

ALTER TABLE subjects ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'draft';
ALTER TABLE lessons ADD COLUMN IF NOT EXISTS assignment_url TEXT;

CREATE INDEX IF NOT EXISTS idx_subjects_status ON subjects(status);

COMMIT;
