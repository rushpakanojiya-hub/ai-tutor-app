-- Replaces all shared/placeholder content with real, subject-specific
-- educational content. Every lesson below gets its own genuine PDF notes
-- (self-hosted from backend/static/notes/, served via /static/*).
--
-- Videos are intentionally set to NULL here: there is no freely available,
-- verified catalog of direct-linkable (.mp4) topic-matched educational
-- videos to seed with honestly. Leaving video_url NULL triggers the
-- existing "No video available for this lesson" empty state rather than
-- showing unrelated placeholder footage. Add real video_url values later
-- once actual lecture videos are recorded/hosted (Cloudinary, S3, etc.) â€”
-- no code change is needed, the player already reads whatever URL is set.

-- 1) New subjects: History (under Academic), English (under Languages).
INSERT INTO subjects (category_id, name, description, thumbnail)
SELECT id, 'History', 'Key events and figures that shaped the modern world.', NULL
FROM course_categories WHERE name = 'Academic'
ON CONFLICT DO NOTHING;

INSERT INTO subjects (category_id, name, description, thumbnail)
SELECT id, 'English', 'Grammar, vocabulary, and writing skills.', NULL
FROM course_categories WHERE name = 'Languages'
ON CONFLICT DO NOTHING;

-- 2) Remove the old cartoon video URLs from the Mathematics lessons â€”
-- see comment above on why no replacement video is seeded here.
UPDATE lessons SET video_url = NULL
WHERE subject_id IN (SELECT id FROM subjects WHERE name = 'Mathematics');

-- 3) Delete the old shared/placeholder notes rows entirely (GitHub PDF.js
-- paper, W3C dummy.pdf) â€” they'll be replaced by real per-lesson notes below.
DELETE FROM notes WHERE lesson_id IN (
    SELECT l.id FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics'
);

-- 4) New lessons for Physics, Chemistry, Flutter, Golang, History, English
-- (3 each, matching Mathematics' existing structure).
INSERT INTO lessons (subject_id, title, description, video_url, pdf_url, duration, order_number)
SELECT s.id, 'Introduction to Physics', 'What physics is and its major branches.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'Physics'
UNION ALL
SELECT s.id, 'Motion and Forces', 'Newton''s three laws of motion explained.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Physics'
UNION ALL
SELECT s.id, 'Energy and Work', 'Kinetic and potential energy, and conservation of energy.', NULL, NULL, 10, 3 FROM subjects s WHERE s.name = 'Physics'
UNION ALL
SELECT s.id, 'Introduction to Chemistry', 'States of matter and physical vs chemical change.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'Chemistry'
UNION ALL
SELECT s.id, 'Atoms and Molecules', 'The building blocks of all matter.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Chemistry'
UNION ALL
SELECT s.id, 'Chemical Reactions', 'How substances transform into new substances.', NULL, NULL, 10, 3 FROM subjects s WHERE s.name = 'Chemistry'
UNION ALL
SELECT s.id, 'Introduction to Flutter', 'What Flutter is and why developers use it.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'Flutter'
UNION ALL
SELECT s.id, 'Widgets and Layouts', 'Stateless vs stateful widgets and common layouts.', NULL, NULL, 12, 2 FROM subjects s WHERE s.name = 'Flutter'
UNION ALL
SELECT s.id, 'State Management', 'Managing app data with the Provider pattern.', NULL, NULL, 12, 3 FROM subjects s WHERE s.name = 'Flutter'
UNION ALL
SELECT s.id, 'Go Language Fundamentals', 'What Go is and writing your first program.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'Golang'
UNION ALL
SELECT s.id, 'Functions and Structs', 'Defining functions, structs, and methods in Go.', NULL, NULL, 10, 2 FROM subjects s WHERE s.name = 'Golang'
UNION ALL
SELECT s.id, 'Concurrency Basics', 'Goroutines and channels for concurrent programs.', NULL, NULL, 10, 3 FROM subjects s WHERE s.name = 'Golang'
UNION ALL
SELECT s.id, 'Ancient Civilizations', 'Mesopotamia, Egypt, the Indus Valley, and ancient China.', NULL, NULL, 10, 1 FROM subjects s WHERE s.name = 'History'
UNION ALL
SELECT s.id, 'World Wars', 'Causes and impact of World War I and II.', NULL, NULL, 12, 2 FROM subjects s WHERE s.name = 'History'
UNION ALL
SELECT s.id, 'Indian Independence Movement', 'Key figures and events leading to independence in 1947.', NULL, NULL, 10, 3 FROM subjects s WHERE s.name = 'History'
UNION ALL
SELECT s.id, 'Grammar Basics', 'Parts of speech, sentence structure, and tenses.', NULL, NULL, 8, 1 FROM subjects s WHERE s.name = 'English'
UNION ALL
SELECT s.id, 'Vocabulary Building', 'Using context clues, prefixes, and suffixes.', NULL, NULL, 8, 2 FROM subjects s WHERE s.name = 'English'
UNION ALL
SELECT s.id, 'Writing Skills', 'The writing process and clear paragraph structure.', NULL, NULL, 10, 3 FROM subjects s WHERE s.name = 'English';

-- 5) Real notes for every lesson across all 7 subjects, each pointing to
-- its own genuine PDF (relative path â€” Flutter resolves the full URL via
-- ApiConstants.resolveMediaUrl so it works on any host/deployment).
INSERT INTO notes (lesson_id, title, pdf_url)
SELECT l.id, l.title || ' Notes', '/static/notes/mathematics-introduction.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics' AND l.title = 'Introduction'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/mathematics-algebra.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics' AND l.title = 'Algebra'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/mathematics-geometry.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Mathematics' AND l.title = 'Geometry'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/physics-introduction.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Physics' AND l.title = 'Introduction to Physics'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/physics-motion-and-forces.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Physics' AND l.title = 'Motion and Forces'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/physics-energy-and-work.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Physics' AND l.title = 'Energy and Work'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/chemistry-introduction.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Chemistry' AND l.title = 'Introduction to Chemistry'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/chemistry-atoms-and-molecules.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Chemistry' AND l.title = 'Atoms and Molecules'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/chemistry-chemical-reactions.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Chemistry' AND l.title = 'Chemical Reactions'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/flutter-introduction.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Flutter' AND l.title = 'Introduction to Flutter'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/flutter-widgets-and-layouts.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Flutter' AND l.title = 'Widgets and Layouts'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/flutter-state-management.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Flutter' AND l.title = 'State Management'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/golang-fundamentals.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Golang' AND l.title = 'Go Language Fundamentals'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/golang-functions-and-structs.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Golang' AND l.title = 'Functions and Structs'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/golang-concurrency-basics.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'Golang' AND l.title = 'Concurrency Basics'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/history-ancient-civilizations.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'History' AND l.title = 'Ancient Civilizations'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/history-world-wars.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'History' AND l.title = 'World Wars'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/history-indian-independence.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'History' AND l.title = 'Indian Independence Movement'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/english-grammar-basics.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'English' AND l.title = 'Grammar Basics'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/english-vocabulary-building.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'English' AND l.title = 'Vocabulary Building'
UNION ALL
SELECT l.id, l.title || ' Notes', '/static/notes/english-writing-skills.pdf' FROM lessons l JOIN subjects s ON s.id = l.subject_id WHERE s.name = 'English' AND l.title = 'Writing Skills';
