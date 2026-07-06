DELETE FROM notes WHERE title LIKE '% - Notes' AND lesson_id IN (
    SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics'
);

UPDATE lessons SET video_url = NULL
WHERE subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');
