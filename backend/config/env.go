package config

import (
	"log"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

var (
	APIKey        string
	BearerToken   string
	BaseDomain    string
	NettifyAPIKey string
)

func LoadEnv() {
	if err := godotenv.Load(); err != nil {
		log.Println("⚠️ No .env file found, using system environment variables")
	}
	APIKey = os.Getenv("API_KEY")
	BearerToken = os.Getenv("BEARER_TOKEN")
	BaseDomain = os.Getenv("DOMAIN")
	NettifyAPIKey = os.Getenv("NETTIFY_API_KEY")

	if APIKey == "" || BearerToken == "" || BaseDomain == "" {
		log.Fatal("❌ Missing API_KEY, BEARER_TOKEN or DOMAIN in .env")
	}

	if NettifyAPIKey == "" {
		log.Println("⚠️ NETTIFY_API_KEY not found in .env - Nettify provider will not work")
	}
}

func MaskString(s string) string {
	if len(s) <= 4 {
		return strings.Repeat("*", len(s))
	}
	return s[:2] + strings.Repeat("*", len(s)-4) + s[len(s)-2:]
}
