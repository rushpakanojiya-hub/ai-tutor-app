UPDATE lessons SET duration = 1
WHERE subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics')
  AND video_url IS NOT NULL;