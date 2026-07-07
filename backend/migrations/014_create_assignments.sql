-- Assignment & AI Auto-Evaluation module, Phase 1: Subject-level targeting
-- only. The assignment_targets table is deliberately polymorphic so
-- future phases (individual student, multiple students, batch,
-- classroom, section, group) can be added by inserting new target_type
-- values - no schema change needed, ever.

BEGIN;

CREATE TABLE IF NOT EXISTS assignments (
    id                SERIAL PRIMARY KEY,
    teacher_id        INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title             VARCHAR(255) NOT NULL,
    description       TEXT,
    instructions      TEXT,
    difficulty        VARCHAR(20) NOT NULL DEFAULT 'medium',
    estimated_minutes INTEGER,
    max_marks         INTEGER NOT NULL DEFAULT 10,
    passing_marks     INTEGER,
    start_date        TIMESTAMPTZ,
    due_date          TIMESTAMPTZ,
    status            VARCHAR(20) NOT NULL DEFAULT 'draft', -- draft | published | unpublished | archived
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Polymorphic targeting - Phase 1 only ever inserts target_type='subject'.
-- Future phases add target_type IN ('student','batch','classroom',
-- 'section','group') with target_id pointing into whichever table that
-- type refers to. No column changes needed to support them later.
CREATE TABLE IF NOT EXISTS assignment_targets (
    id            SERIAL PRIMARY KEY,
    assignment_id INTEGER NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
    target_type   VARCHAR(20) NOT NULL,
    target_id     INTEGER NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assignment_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_assignment_targets_lookup ON assignment_targets(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_assignment_targets_assignment ON assignment_targets(assignment_id);

CREATE TABLE IF NOT EXISTS assignment_submissions (
    id              SERIAL PRIMARY KEY,
    assignment_id   INTEGER NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
    student_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    submission_text TEXT,
    status          VARCHAR(20) NOT NULL DEFAULT 'draft', -- draft | submitted | under_review | evaluated | returned
    submitted_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assignment_id, student_id)
);

CREATE TABLE IF NOT EXISTS assignment_evaluations (
    id                     SERIAL PRIMARY KEY,
    submission_id          INTEGER NOT NULL UNIQUE REFERENCES assignment_submissions(id) ON DELETE CASCADE,
    ai_score               INTEGER,
    max_score              INTEGER,
    percentage             NUMERIC(5,2),
    strengths              JSONB,
    weaknesses             JSONB,
    missing_concepts       JSONB,
    suggestions            TEXT,
    teacher_override_score INTEGER,
    teacher_feedback       TEXT,
    reviewed_by_teacher    BOOLEAN NOT NULL DEFAULT false,
    evaluated_at           TIMESTAMPTZ,
    reviewed_at            TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assignments_teacher ON assignments(teacher_id);
CREATE INDEX IF NOT EXISTS idx_assignments_status ON assignments(status);
CREATE INDEX IF NOT EXISTS idx_assignment_submissions_assignment ON assignment_submissions(assignment_id);
CREATE INDEX IF NOT EXISTS idx_assignment_submissions_student ON assignment_submissions(student_id);

COMMIT;
