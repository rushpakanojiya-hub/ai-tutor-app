-- QA fix: "Duplicate email registration race condition" - the app-level
-- SELECT EXISTS check in auth.Repository.CreateUser has a classic
-- time-of-check-to-time-of-use gap: two concurrent registrations with
-- the same email can both pass the check before either INSERTs. A DB-
-- level UNIQUE constraint is the only thing that actually closes this -
-- the app-level check becomes just a fast/friendly pre-check, backed by
-- this as the real guarantee.

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_idx ON users(email);

COMMIT;
