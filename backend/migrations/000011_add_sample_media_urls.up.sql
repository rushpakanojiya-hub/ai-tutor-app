-- Adds real, publicly hosted sample video/PDF URLs to the seeded lessons
-- (migration 000009 left video_url/pdf_url NULL) so video playback and PDF
-- notes can actually be tested end-to-end, not just their empty states.
UPDATE lessons SET
    video_url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'
WHERE title = 'Introduction' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

UPDATE lessons SET
    video_url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4'
WHERE title = 'Algebra' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

UPDATE lessons SET
    video_url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4'
WHERE title = 'Geometry' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

-- Sample PDF notes (W3C's public dummy.pdf) attached to each Mathematics lesson.
INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, l.title || ' - Notes', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'
FROM lessons l
JOIN subjects s ON s.id = l.subject_id
WHERE s.name = 'Mathematics';
