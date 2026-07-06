-- Adds a real, lesson-specific video to every lesson: a short slide-video
-- rendered directly from that lesson's own PDF notes (backend/static/videos/),
-- so the video content always matches the lesson topic exactly — no
-- generic/unrelated footage. Self-hosted via the same /static/* route
-- already used for PDF notes (see migration 000014 and main.go).
UPDATE lessons SET video_url = '/static/videos/mathematics-introduction.mp4'
WHERE title = 'Introduction' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

UPDATE lessons SET video_url = '/static/videos/mathematics-algebra.mp4'
WHERE title = 'Algebra' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

UPDATE lessons SET video_url = '/static/videos/mathematics-geometry.mp4'
WHERE title = 'Geometry' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

UPDATE lessons SET video_url = '/static/videos/physics-introduction.mp4'
WHERE title = 'Introduction to Physics' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Physics');

UPDATE lessons SET video_url = '/static/videos/physics-motion-and-forces.mp4'
WHERE title = 'Motion and Forces' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Physics');

UPDATE lessons SET video_url = '/static/videos/physics-energy-and-work.mp4'
WHERE title = 'Energy and Work' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Physics');

UPDATE lessons SET video_url = '/static/videos/chemistry-introduction.mp4'
WHERE title = 'Introduction to Chemistry' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Chemistry');

UPDATE lessons SET video_url = '/static/videos/chemistry-atoms-and-molecules.mp4'
WHERE title = 'Atoms and Molecules' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Chemistry');

UPDATE lessons SET video_url = '/static/videos/chemistry-chemical-reactions.mp4'
WHERE title = 'Chemical Reactions' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Chemistry');

UPDATE lessons SET video_url = '/static/videos/flutter-introduction.mp4'
WHERE title = 'Introduction to Flutter' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Flutter');

UPDATE lessons SET video_url = '/static/videos/flutter-widgets-and-layouts.mp4'
WHERE title = 'Widgets and Layouts' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Flutter');

UPDATE lessons SET video_url = '/static/videos/flutter-state-management.mp4'
WHERE title = 'State Management' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Flutter');

UPDATE lessons SET video_url = '/static/videos/golang-fundamentals.mp4'
WHERE title = 'Go Language Fundamentals' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Golang');

UPDATE lessons SET video_url = '/static/videos/golang-functions-and-structs.mp4'
WHERE title = 'Functions and Structs' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Golang');

UPDATE lessons SET video_url = '/static/videos/golang-concurrency-basics.mp4'
WHERE title = 'Concurrency Basics' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Golang');

UPDATE lessons SET video_url = '/static/videos/history-ancient-civilizations.mp4'
WHERE title = 'Ancient Civilizations' AND subject_id IN (SELECT id FROM subjects WHERE name = 'History');

UPDATE lessons SET video_url = '/static/videos/history-world-wars.mp4'
WHERE title = 'World Wars' AND subject_id IN (SELECT id FROM subjects WHERE name = 'History');

UPDATE lessons SET video_url = '/static/videos/history-indian-independence.mp4'
WHERE title = 'Indian Independence Movement' AND subject_id IN (SELECT id FROM subjects WHERE name = 'History');

UPDATE lessons SET video_url = '/static/videos/english-grammar-basics.mp4'
WHERE title = 'Grammar Basics' AND subject_id IN (SELECT id FROM subjects WHERE name = 'English');

UPDATE lessons SET video_url = '/static/videos/english-vocabulary-building.mp4'
WHERE title = 'Vocabulary Building' AND subject_id IN (SELECT id FROM subjects WHERE name = 'English');

UPDATE lessons SET video_url = '/static/videos/english-writing-skills.mp4'
WHERE title = 'Writing Skills' AND subject_id IN (SELECT id FROM subjects WHERE name = 'English');
