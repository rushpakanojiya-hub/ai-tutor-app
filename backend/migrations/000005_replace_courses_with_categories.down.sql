-- Note: this rolls back to an empty state, not the exact old Day 1 schema
-- (those tables were unused placeholders, not worth reconstructing).
DROP TABLE IF EXISTS course_categories;