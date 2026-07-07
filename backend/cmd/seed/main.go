// Command seed creates three default development/testing accounts
// (admin, teacher, student) - never run in production, and never
// overwrites an existing account with the same email.
//
// Admin accounts can ONLY be created this way (or via direct SQL) -
// there is no admin registration path anywhere in the app, by design.
//
// Run from the backend/ folder:
//
//	go run cmd/seed/main.go
package main

import (
	"database/sql"
	"fmt"
	"log"

	"ai-tutor-backend/configs"
	"ai-tutor-backend/database"
	"ai-tutor-backend/utils"
)

type seedAccount struct {
	Name     string
	Email    string
	Password string
	Role     string
}

func main() {
	cfg := configs.LoadConfig()

	if cfg.AppEnv != "development" {
		log.Fatalf("Refusing to seed: APP_ENV is %q, not \"development\". Seed accounts are for local/dev use only.", cfg.AppEnv)
	}

	db := database.Connect(cfg)
	defer db.Close()

	accounts := []seedAccount{
		{Name: "Admin", Email: "admin@aitutor.com", Password: "Admin@123", Role: "admin"},
		{Name: "Teacher", Email: "teacher@aitutor.com", Password: "Teacher@123", Role: "teacher"},
		{Name: "Student", Email: "student@aitutor.com", Password: "Student@123", Role: "student"},
	}

	for _, acc := range accounts {
		exists, err := emailExists(db, acc.Email)
		if err != nil {
			log.Printf("Failed to check %s: %v", acc.Email, err)
			continue
		}
		if exists {
			fmt.Printf("Skipping %s (%s) - already exists.\n", acc.Role, acc.Email)
			continue
		}

		hash, err := utils.HashPassword(acc.Password)
		if err != nil {
			log.Printf("Failed to hash password for %s: %v", acc.Email, err)
			continue
		}

		_, err = db.Exec(`
			INSERT INTO users (name, email, password_hash, role, status)
			VALUES ($1, $2, $3, $4, 'active')`,
			acc.Name, acc.Email, hash, acc.Role,
		)
		if err != nil {
			log.Printf("Failed to create %s: %v", acc.Email, err)
			continue
		}
		fmt.Printf("Created %s: %s / %s\n", acc.Role, acc.Email, acc.Password)
	}

	fmt.Println("\nSeeding complete.")
}

func emailExists(db *sql.DB, email string) (bool, error) {
	var exists bool
	err := db.QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)`, email).Scan(&exists)
	return exists, err
}
