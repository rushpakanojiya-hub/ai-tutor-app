-- Lightweight enrollment: a student becomes "enrolled" in a subject the
-- first time they complete any lesson in it (see progress.Service hook).
-- Used to gate assignment visibility (only enrolled students see a
-- subject's assignments) without touching lesson access anywhere else.

BEGIN;

CREATE TABLE IF NOT EXISTS subject_enrollments (
    id          SERIAL PRIMARY KEY,
    student_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject_id  INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (student_id, subject_id)
);

CREATE INDEX IF NOT EXISTS idx_subject_enrollments_student ON subject_enrollments(student_id);
CREATE INDEX IF NOT EXISTS idx_subject_enrollments_subject ON subject_enrollments(subject_id);

COMMIT;
