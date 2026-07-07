-- Attendance: self-check-in model. There's no video infra to
-- automatically detect join/leave, so a student taps "I'm Present"
-- during the scheduled class window; checking in within the first 10
-- minutes of start counts as "present", after that as "late". "Absent"
-- is never stored - it's simply the absence of a row once class has ended.

BEGIN;

CREATE TABLE IF NOT EXISTS live_class_attendance (
    id            SERIAL PRIMARY KEY,
    live_class_id INTEGER NOT NULL REFERENCES live_classes(id) ON DELETE CASCADE,
    student_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    checked_in_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status        VARCHAR(20) NOT NULL, -- present | late
    UNIQUE (live_class_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_attendance_class ON live_class_attendance(live_class_id);
CREATE INDEX IF NOT EXISTS idx_attendance_student ON live_class_attendance(student_id);

-- Notifications: simple polling-based (fetched on app open/refresh) -
-- no WebSocket/push infra exists yet. Covers synchronous events (class
-- created, class cancelled) fine; a "starting soon" reminder would need
-- a background scheduler, which doesn't exist, so the countdown timer in
-- the UI covers that signal instead.
CREATE TABLE IF NOT EXISTS notifications (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type       VARCHAR(40) NOT NULL, -- new_live_class | live_class_cancelled
    title      VARCHAR(255) NOT NULL,
    body       TEXT,
    related_id INTEGER,
    is_read    BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);

COMMIT;
