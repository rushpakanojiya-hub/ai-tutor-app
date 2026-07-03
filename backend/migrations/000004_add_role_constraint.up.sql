-- The "role" column and its 'student' default already exist from migration
-- 000001. This migration only ADDS a CHECK constraint so the database itself
-- rejects any role outside the known set, keeping it in sync with
-- internal/constants/roles.go as Teacher/Parent/Admin get built out.
ALTER TABLE users
    ADD CONSTRAINT chk_users_role
    CHECK (role IN ('student', 'teacher', 'parent', 'admin'));