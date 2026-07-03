// Package configs loads and exposes application configuration
// read from environment variables (or a local .env file during development).
package configs

import (
	"fmt"
	"log"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

// Config holds every configurable value the app needs.
type Config struct {
	Port    string
	GinMode string
	AppEnv  string // "development", "production", etc. Informational (health check, logs).

	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	DBSSLMode  string

	// DatabaseURL, if set, takes priority over the individual DB_* fields
	// above. This is the form Docker Compose / Render / most hosts prefer
	// (a single connection string), while local dev can keep using the
	// separate DB_HOST/DB_PORT/etc. vars from Day 1 — both are supported.
	DatabaseURL string

	JWTSecret            string
	JWTAccessExpiryMin   int
	JWTRefreshExpiryDays int
}

// LoadConfig reads the .env file (if present) and environment variables,
// returning a populated Config. Missing values fall back to sane defaults
// so the app can still boot in development.
func LoadConfig() *Config {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, relying on system environment variables")
	}

	return &Config{
		Port:    getEnv("PORT", "8080"),
		GinMode: getEnv("GIN_MODE", "debug"),
		AppEnv:  getEnv("APP_ENV", "development"),

		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", "postgres"),
		DBPassword: getEnv("DB_PASSWORD", "root"),
		DBName:     getEnv("DB_NAME", "ai_tutor_db"),
		DBSSLMode:  getEnv("DB_SSLMODE", "disable"),

		DatabaseURL: getEnv("DATABASE_URL", ""),

		JWTSecret:            getEnv("JWT_SECRET", "insecure_dev_secret_change_me"),
		JWTAccessExpiryMin:   getEnvAsInt("JWT_ACCESS_EXPIRY_MINUTES", 60),
		JWTRefreshExpiryDays: getEnvAsInt("JWT_REFRESH_EXPIRY_DAYS", 7),
	}
}

// DSN builds the PostgreSQL connection string. If DATABASE_URL is set, it is
// used as-is (Docker/production style). Otherwise it's assembled from the
// individual DB_* fields, exactly as Day 1 did.
func (c *Config) DSN() string {
	if c.DatabaseURL != "" {
		return c.DatabaseURL
	}
	return fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		c.DBHost, c.DBPort, c.DBUser, c.DBPassword, c.DBName, c.DBSSLMode,
	)
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}
	return fallback
}

func getEnvAsInt(key string, fallback int) int {
	if value, ok := os.LookupEnv(key); ok {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return fallback
}