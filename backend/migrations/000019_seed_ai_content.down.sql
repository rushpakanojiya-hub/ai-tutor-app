DELETE FROM lesson_ai_content WHERE lesson_id IN (
    SELECT l.id FROM lessons l WHERE l.title IN (
        'Introduction', 'Algebra', 'Geometry', 'Introduction to Physics',
        'Introduction to Chemistry', 'Introduction to Biology',
        'Ancient Civilizations', 'Indian Independence Movement',
        'Introduction to Flutter', 'Go Language Fundamentals'
    )
);
DELETE FROM lessons WHERE title = 'Introduction to Biology' AND subject_id IN (SELECT id FROM subjects WHERE name = 'Biology');
