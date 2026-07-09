-- Certificates: one per (student, subject) - a subject IS "the course"
-- a student completes end-to-end. course_name/subject_name/
-- instructor_name are snapshotted at issue time so a certificate's
-- content never silently changes if the subject is later renamed or
-- reassigned.

BEGIN;

CREATE TABLE IF NOT EXISTS certificates (
    id SERIAL PRIMARY KEY,
    certificate_code VARCHAR(50) UNIQUE NOT NULL,
    student_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
    course_name VARCHAR(255) NOT NULL,
    subject_name VARCHAR(255) NOT NULL,
    instructor_name VARCHAR(255) NOT NULL,
    final_score NUMERIC(5,2) NOT NULL,
    grade VARCHAR(5) NOT NULL,
    completion_date DATE NOT NULL,
    issue_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(student_id, subject_id)
);

CREATE INDEX IF NOT EXISTS idx_certificates_student ON certificates(student_id);
CREATE INDEX IF NOT EXISTS idx_certificates_subject ON certificates(subject_id);

COMMIT;
