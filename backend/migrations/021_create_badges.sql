-- Badges: 7 fixed badge definitions + a join table tracking which
-- students have earned which ones and when.

BEGIN;

CREATE TABLE IF NOT EXISTS badges (
    id SERIAL PRIMARY KEY,
    key VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    icon_key VARCHAR(50) NOT NULL
);

INSERT INTO badges (key, name, description, icon_key) VALUES
    ('quiz_master', 'Quiz Master', 'Passed 10 or more quizzes', 'quiz'),
    ('homework_hero', 'Homework Hero', 'Submitted 5 or more assignments', 'homework'),
    ('study_streak_7', '7-Day Study Streak', 'Maintained a 7-day learning streak', 'streak'),
    ('math_champion', 'Math Champion', 'Passed 5 or more Math quizzes', 'math'),
    ('perfect_score', 'Perfect Score', 'Scored 100% on a quiz', 'perfect'),
    ('course_finisher', 'Course Finisher', 'Completed every lesson in a subject', 'course'),
    ('attendance_star', 'Attendance Star', 'Attended every live class in a subject', 'attendance')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS student_badges (
    id SERIAL PRIMARY KEY,
    student_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    badge_id INTEGER NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
    earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(student_id, badge_id)
);

COMMIT;
