// Package database owns the PostgreSQL connection pool used by the whole app.
package database

import (
	"database/sql"
	"log"
	"time"

	_ "github.com/lib/pq"

	"ai-tutor-backend/configs"
)

// Connect opens a PostgreSQL connection pool using the given config,
// verifies it with a ping, and tunes basic pool settings.
// It intentionally panics on failure because the API is useless without a DB.
func Connect(cfg *configs.Config) *sql.DB {
	db, err := sql.Open("postgres", cfg.DSN())
	if err != nil {
		log.Fatalf("failed to open database connection: %v", err)
	}

	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}

	log.Println("Connected to PostgreSQL successfully")
	return db
}