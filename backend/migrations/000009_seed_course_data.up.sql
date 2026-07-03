-- Sample data so the Flutter screens have something to render immediately.
-- Uses INSERT ... RETURNING via CTEs to wire up foreign keys without
-- hardcoding IDs (safe to run on a fresh database).

-- Categories
WITH cat_academic AS (
    INSERT INTO course_categories (name, icon) VALUES ('Academic', 'school') RETURNING id
),
cat_science AS (
    INSERT INTO course_categories (name, icon) VALUES ('Science', 'science') RETURNING id
),
cat_programming AS (
    INSERT INTO course_categories (name, icon) VALUES ('Programming', 'code') RETURNING id
),
cat_mathematics AS (
    INSERT INTO course_categories (name, icon) VALUES ('Mathematics', 'calculate') RETURNING id
),
cat_languages AS (
    INSERT INTO course_categories (name, icon) VALUES ('Languages', 'translate') RETURNING id
),
cat_competitive AS (
    INSERT INTO course_categories (name, icon) VALUES ('Competitive Exams', 'emoji_events') RETURNING id
),

-- Subjects under Academic -> Mathematics
subj_mathematics AS (
    INSERT INTO subjects (category_id, name, description, thumbnail)
    SELECT id, 'Mathematics', 'Core mathematics concepts for school students.', NULL FROM cat_academic
    RETURNING id
),

-- Subjects under Science
subj_physics AS (
    INSERT INTO subjects (category_id, name, description, thumbnail)
    SELECT id, 'Physics', 'Fundamentals of physics: motion, energy, and forces.', NULL FROM cat_science
    RETURNING id
),
subj_chemistry AS (
    INSERT INTO subjects (category_id, name, description, thumbnail)
    SELECT id, 'Chemistry', 'Introduction to elements, compounds, and reactions.', NULL FROM cat_science
    RETURNING id
),
subj_biology AS (
    INSERT INTO subjects (category_id, name, description, thumbnail)
    SELECT id, 'Biology', 'Life sciences: cells, genetics, and ecosystems.', NULL FROM cat_science
    RETURNING id
),

-- Subjects under Programming
subj_flutter AS (
    INSERT INTO subjects (category_id, name, description, thumbnail)
    SELECT id, 'Flutter', 'Build cross-platform apps with Flutter and Dart.', NULL FROM cat_programming
    RETURNING id
),
subj_golang AS (
    INSERT INTO subjects (category_id, name, description, thumbnail)
    SELECT id, 'Golang', 'Backend development with Go and the Gin framework.', NULL FROM cat_programming
    RETURNING id
),
subj_postgresql AS (
    INSERT INTO subjects (category_id, name, description, thumbnail)
    SELECT id, 'PostgreSQL', 'Relational databases and SQL fundamentals.', NULL FROM cat_programming
    RETURNING id
)

-- Lessons under Mathematics
INSERT INTO lessons (subject_id, title, description, video_url, pdf_url, duration, order_number)
SELECT id, 'Introduction', 'Overview of what this course covers.', NULL, NULL, 10, 1 FROM subj_mathematics
UNION ALL
SELECT id, 'Algebra', 'Variables, expressions, and equations.', NULL, NULL, 20, 2 FROM subj_mathematics
UNION ALL
SELECT id, 'Geometry', 'Shapes, angles, and spatial reasoning.', NULL, NULL, 25, 3 FROM subj_mathematics;