-- Restricts users.role to exactly three values at the database level -
-- belt-and-suspenders on top of the backend already never accepting role
-- from the frontend (RegisterRequest/TeacherApplyRequest have no role
-- field; the backend always assigns constants.RoleStudent /
-- constants.RoleTeacher itself). This constraint just makes it
-- impossible for any future code path to insert an invalid role, even
-- by accident.

BEGIN;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('admin', 'teacher', 'student'));

COMMIT;
