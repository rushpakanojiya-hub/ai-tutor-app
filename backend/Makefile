# Day 1 developer shortcuts. Run `make help` to see this list.
# These wrap the exact commands from the README so nobody has to remember
# the long-form psql/docker/go invocations.

.PHONY: help run build test docker docker-down migrate migrate-down

help:
	@echo "make run           - run the backend locally (go run main.go)"
	@echo "make build         - compile a local binary into ./bin"
	@echo "make test          - run Go tests"
	@echo "make docker        - build and start postgres + backend via Docker Compose"
	@echo "make docker-down   - stop and remove the Docker Compose stack"
	@echo "make migrate       - apply all pending SQL migrations (local psql)"
	@echo "make migrate-down  - roll back the most recent migration (local psql)"

run:
	go run main.go

build:
	go build -o bin/ai-tutor-backend .

test:
	go test ./...

docker:
	docker compose up --build

docker-down:
	docker compose down

# Applies every *.up.sql file in order using the DB_* values from .env.
# Requires `psql` on PATH and a running Postgres (local or `make docker`).
migrate:
	@for f in migrations/*.up.sql; do \
		echo "Applying $$f"; \
		psql -U $${DB_USER:-postgres} -d $${DB_NAME:-ai_tutor_db} -f $$f; \
	done

# Rolls back only the highest-numbered migration (down file), one step.
migrate-down:
	@latest=$$(ls migrations/*.down.sql | sort | tail -n 1); \
	echo "Rolling back $$latest"; \
	psql -U $${DB_USER:-postgres} -d $${DB_NAME:-ai_tutor_db} -f $$latest