-- Adds an editorial difficulty tag to subjects (Beginner/Intermediate/
-- Advanced). This is a genuine content classification set by us, not a
-- fabricated statistic - unlike ratings or quiz/mock-test counts, which
-- stay out of the UI until those systems actually exist.

BEGIN;

ALTER TABLE subjects ADD COLUMN IF NOT EXISTS difficulty VARCHAR(20) NOT NULL DEFAULT 'Intermediate';

-- Academic: foundational/awareness subjects -> Beginner
UPDATE subjects SET difficulty = 'Beginner'
WHERE name IN ('English', 'History', 'Geography', 'Social Science', 'Economics', 'General Knowledge');

-- Academic: subjects requiring more conceptual depth -> Intermediate
UPDATE subjects SET difficulty = 'Intermediate'
WHERE name IN ('Mathematics', 'Physics', 'Chemistry', 'Biology', 'Computer Science');

-- Competitive Exams: all exam prep is Advanced by nature
UPDATE subjects SET difficulty = 'Advanced'
WHERE category_id = (SELECT id FROM course_categories WHERE name = 'Competitive Exams');

-- Programming subjects stay Intermediate (already the default, explicit for clarity)
UPDATE subjects SET difficulty = 'Intermediate'
WHERE name IN ('Flutter', 'Golang', 'PostgreSQL');

COMMIT;
