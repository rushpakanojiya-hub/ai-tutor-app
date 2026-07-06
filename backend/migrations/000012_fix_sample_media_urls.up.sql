UPDATE lessons SET
    video_url = 'https://www.w3schools.com/html/mov_bbb.mp4'
WHERE subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics')
  AND video_url IS NOT NULL;

UPDATE notes SET
    pdf_url = 'https://raw.githubusercontent.com/mozilla/pdf.js/master/web/compressed.tracemonkey-pldi-09.pdf'
WHERE title LIKE '% - Notes';