package main

import (
	"log"
	"net/http"
	"time"

	"oceanproxy-api/config"
	"oceanproxy-api/handlers"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func main() {
	log.Println("🚀 Starting OceanProxy API Server...")

	config.LoadEnv()

	log.Printf("🔧 Config loaded - API_KEY: %s, BEARER_TOKEN: %s, DOMAIN: %s",
		config.MaskString(config.APIKey),
		config.MaskString(config.BearerToken),
		config.BaseDomain)

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		handlers.JSON(w, map[string]string{
			"status":    "healthy",
			"timestamp": time.Now().Format(time.RFC3339),
		})
	})

	r.Group(func(r chi.Router) {
		r.Use(handlers.AuthMiddleware)
		r.Post("/plan", handlers.CreatePlanHandler)                // proxies.fo
		r.Post("/nettify/plan", handlers.CreateNettifyPlanHandler) // nettify
		r.Get("/proxies", handlers.GetProxiesHandler)
		r.Post("/restore", handlers.RestoreHandler)
	})

	log.Println("🌐 Listening on http://0.0.0.0:9090")
	log.Fatal(http.ListenAndServe(":9090", r))
}
