// Package configs loads and exposes application configuration
// read from environment variables (or a local .env file during development).
package configs

import (
	"crypto/rand"
	"encoding/hex"
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
	// separate DB_HOST/DB_PORT/etc. vars from Day 1 - both are supported.
	DatabaseURL string

	JWTSecret            string
	JWTAccessExpiryMin   int
	JWTRefreshExpiryDays int

	// Groq API - powers the real LLM AI Tutor (internal/ai/groq_client.go).
	GroqAPIKey string
	GroqAPIURL string
	GroqModel  string

	// YouTube Data API v3 - powers per-lesson recommended videos
	// (internal/youtube/youtube_client.go). Supports multiple comma-separated
	// keys for quota rotation, e.g. YOUTUBE_API_KEY=key1,key2,key3
	YoutubeAPIKeys    []string
	YoutubeMaxResults int

	// LiveKit - powers real video calling for Live Classes
	// (internal/livekit). Get these from cloud.livekit.io project settings.
	LiveKitURL       string
	LiveKitAPIKey    string
	LiveKitAPISecret string

	// Cloudinary - powers Class Resources file uploads (internal/resource).
	CloudinaryCloudName string
	CloudinaryAPIKey    string
	CloudinaryAPISecret string

	// Security audit fix (High: "CORS") - configurable list of allowed
	// origins instead of a hardcoded wildcard ("*"). Only affects
	// browser-based clients (CORS is not enforced for native mobile
	// HTTP requests) - set to the real deployed web domain(s) when one
	// exists.
	AllowedOrigins []string
}

// LoadConfig reads the .env file (if present) and environment variables,
// returning a populated Config. Missing values fall back to sane defaults
// so the app can still boot in development.
func LoadConfig() *Config {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, relying on system environment variables")
	}

	appEnv := getEnv("APP_ENV", "development")

	cfg := &Config{
		Port:    getEnv("PORT", "8080"),
		GinMode: getEnv("GIN_MODE", "debug"),
		AppEnv:  appEnv,

		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", "postgres"),
		DBPassword: getEnv("DB_PASSWORD", "root"),
		DBName:     getEnv("DB_NAME", "ai_tutor_db"),
		DBSSLMode:  getEnv("DB_SSLMODE", "disable"),

		DatabaseURL: getEnv("DATABASE_URL", ""),

		JWTSecret:            getEnv("JWT_SECRET", ""),
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

		AllowedOrigins: parseCommaList(getEnv("CORS_ORIGINS", "https://d32oc473al3i86.cloudfront.net,http://localhost:3000,http://localhost:8080")),
	}

	// Security fix (QA: "Hardcoded JWT secret") - the old code always fell
	// back to a hardcoded string ("insecure_dev_secret_change_me") when
	// JWT_SECRET wasn't set, silently signing every token with a secret
	// that's visible in the source code. Now:
	//   - production: refuses to start without a real JWT_SECRET, instead
	//     of quietly issuing forgeable tokens.
	//   - development: generates a random secret per run if none is set,
	//     so local/dev boots still work with zero setup, but every restart
	//     invalidates old tokens rather than reusing a known value.
	if cfg.JWTSecret == "" {
		if appEnv == "production" {
			log.Fatal("[FATAL] JWT_SECRET must be set in production - refusing to start with no secret")
		}
		generated, err := generateRandomSecret(32)
		if err != nil {
			log.Fatalf("[FATAL] Could not generate a fallback JWT secret: %v", err)
		}
		log.Println("[WARNING] JWT_SECRET not set - using a randomly generated development-only secret. Set JWT_SECRET in .env for stable sessions across restarts.")
		cfg.JWTSecret = generated
	}

	return cfg
}

func generateRandomSecret(numBytes int) (string, error) {
	b := make([]byte, numBytes)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("failed to generate random secret: %w", err)
	}
	return hex.EncodeToString(b), nil
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
