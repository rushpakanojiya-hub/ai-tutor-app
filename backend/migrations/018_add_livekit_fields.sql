-- Adds real meeting state on top of the existing schedule/calendar
-- fields. meeting_status is separate from the existing `status` column
-- (scheduled/completed/cancelled) - this tracks the actual video session
-- lifecycle (not_started -> live -> ended), independent of whether the
-- teacher later marks the class "completed".

BEGIN;

ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS room_name VARCHAR(100) UNIQUE;
ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS meeting_status VARCHAR(20) NOT NULL DEFAULT 'not_started';
ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;
ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;

COMMIT;
