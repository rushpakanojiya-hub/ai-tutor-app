DELETE FROM notes WHERE pdf_url LIKE '/static/notes/%';
DELETE FROM lessons WHERE subject_id IN (
    SELECT id FROM subjects WHERE name IN ('Physics', 'Chemistry', 'Flutter', 'Golang', 'History', 'English')
);
DELETE FROM subjects WHERE name IN ('History', 'English');
