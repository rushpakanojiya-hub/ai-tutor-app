-- Day 1 created placeholder "courses" and "lessons" tables that no feature
-- ever used. Day 2 replaces them with a proper hierarchy:
-- course_categories -> subjects -> lessons -> notes.
-- Drop the old, unused tables first (lessons references courses via FK,
-- so it must go first) before introducing the new schema.
DROP TABLE IF EXISTS lessons;
DROP TABLE IF EXISTS courses;

CREATE TABLE IF NOT EXISTS course_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    icon VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);