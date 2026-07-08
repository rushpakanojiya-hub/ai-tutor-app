-- Class Resources: real files (PDF/PPT/images/docs/video) a teacher
-- uploads for a live class, stored on Cloudinary. Students can view/
-- download the list; only the uploading teacher can delete.

BEGIN;

CREATE TABLE IF NOT EXISTS class_resources (
    id               SERIAL PRIMARY KEY,
    live_class_id    INTEGER NOT NULL REFERENCES live_classes(id) ON DELETE CASCADE,
    teacher_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_name        VARCHAR(255) NOT NULL,
    file_type        VARCHAR(50) NOT NULL,
    file_url         TEXT NOT NULL,
    cloudinary_id    VARCHAR(255) NOT NULL,
    file_size_bytes  BIGINT NOT NULL DEFAULT 0,
    uploaded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_class_resources_class ON class_resources(live_class_id);

COMMIT;
