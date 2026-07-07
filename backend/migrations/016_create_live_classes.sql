-- Live Class scheduling (Phase 1: calendar/schedule only - no video
-- infrastructure). Status is computed as "missed" dynamically for any
-- class whose end time has passed while still "scheduled" - no
-- background job needed for that.

BEGIN;

CREATE TABLE IF NOT EXISTS live_classes (
    id               SERIAL PRIMARY KEY,
    teacher_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject_id       INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
    lesson_id        INTEGER REFERENCES lessons(id) ON DELETE SET NULL,
    title            VARCHAR(255) NOT NULL,
    description      TEXT,
    class_date       DATE NOT NULL,
    start_time       TIME NOT NULL,
    end_time         TIME NOT NULL,
    max_students     INTEGER,
    is_public        BOOLEAN NOT NULL DEFAULT true,
    meeting_password VARCHAR(50),
    record_class     BOOLEAN NOT NULL DEFAULT false,
    status           VARCHAR(20) NOT NULL DEFAULT 'scheduled', -- scheduled | completed | cancelled
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_live_classes_teacher ON live_classes(teacher_id);
CREATE INDEX IF NOT EXISTS idx_live_classes_subject ON live_classes(subject_id);
CREATE INDEX IF NOT EXISTS idx_live_classes_date ON live_classes(class_date);

COMMIT;
