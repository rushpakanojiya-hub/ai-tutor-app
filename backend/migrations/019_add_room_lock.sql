-- Adds a "locked" flag so a teacher can prevent new students from
-- joining an in-progress class (existing participants stay connected).

BEGIN;

ALTER TABLE live_classes ADD COLUMN IF NOT EXISTS locked BOOLEAN NOT NULL DEFAULT false;

COMMIT;
