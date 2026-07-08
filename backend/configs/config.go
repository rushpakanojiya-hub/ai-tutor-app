// Package configs loads and exposes application configuration
// read from environment variables (or a local .env file during development).
package configs

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"

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

	// Groq API — powers the real LLM AI Tutor (internal/ai/groq_client.go).
	GroqAPIKey string
	GroqAPIURL string
	GroqModel  string

	// YouTube Data API v3 — powers per-lesson recommended videos
	// (internal/youtube/youtube_client.go). Supports multiple comma-separated
	// keys for quota rotation, e.g. YOUTUBE_API_KEY=key1,key2,key3
	YoutubeAPIKeys    []string
	YoutubeMaxResults int

	// LiveKit — powers real video calling for Live Classes
	// (internal/livekit). Get these from cloud.livekit.io project settings.
	LiveKitURL       string
	LiveKitAPIKey    string
	LiveKitAPISecret string

	// Cloudinary — powers Class Resources file uploads (internal/resource).
	CloudinaryCloudName string
	CloudinaryAPIKey    string
	CloudinaryAPISecret string
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

		GroqAPIKey: getEnv("GROQ_API_KEY", ""),
		GroqAPIURL: getEnv("GROQ_API_URL", "https://api.groq.com/openai/v1/chat/completions"),
		GroqModel:  getEnv("GROQ_MODEL", "llama-3.3-70b-versatile"),

		YoutubeAPIKeys:    parseCommaList(getEnv("YOUTUBE_API_KEY", "")),
		YoutubeMaxResults: getEnvAsInt("YOUTUBE_MAX_RESULTS", 5),

		LiveKitURL:       getEnv("LIVEKIT_URL", ""),
		LiveKitAPIKey:    getEnv("LIVEKIT_API_KEY", ""),
		LiveKitAPISecret: getEnv("LIVEKIT_API_SECRET", ""),

		CloudinaryCloudName: getEnv("CLOUDINARY_CLOUD_NAME", ""),
		CloudinaryAPIKey:    getEnv("CLOUDINARY_API_KEY", ""),
		CloudinaryAPISecret: getEnv("CLOUDINARY_API_SECRET", ""),
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

// parseCommaList splits a comma-separated env value into a trimmed,
// non-empty slice. Used for YOUTUBE_API_KEY=key1,key2,key3 style rotation.
func parseCommaList(value string) []string {
	if value == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			result = append(result, p)
		}
	}
	return result
}
