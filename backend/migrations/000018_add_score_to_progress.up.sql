-- Lets "Mark Complete" optionally record a quiz score alongside completion.
ALTER TABLE lesson_progress ADD COLUMN IF NOT EXISTS score INTEGER;
