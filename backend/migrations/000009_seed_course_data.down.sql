-- Removes only the seeded rows by name/title, safe even if the user added
-- their own categories/subjects with different names afterward.
DELETE FROM lessons WHERE title IN ('Introduction', 'Algebra', 'Geometry');
DELETE FROM subjects WHERE name IN ('Mathematics', 'Physics', 'Chemistry', 'Biology', 'Flutter', 'Golang', 'PostgreSQL');
DELETE FROM course_categories WHERE name IN ('Academic', 'Science', 'Programming', 'Mathematics', 'Languages', 'Competitive Exams');