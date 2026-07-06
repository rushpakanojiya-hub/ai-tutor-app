UPDATE lessons SET duration = 10 WHERE title = 'Introduction' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');
UPDATE lessons SET duration = 20 WHERE title = 'Algebra' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');
UPDATE lessons SET duration = 25 WHERE title = 'Geometry' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');