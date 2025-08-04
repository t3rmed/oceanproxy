package main

import (
	"log"
	"net/http"
	"time"

	"oceanproxy-api/config"
	"oceanproxy-api/handlers"
	"oceanproxy-api/proxy"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func main() {
	log.Println("🚀 Starting OceanProxy API Server...")

	config.LoadEnv()

	// Initialize port manager
	if err := proxy.InitializePortManager(); err != nil {
		log.Printf("⚠️ Failed to initialize port manager: %v", err)
	} else {
		log.Println("✅ Port manager initialized")
	}

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
		r.Post("/plan", handlers.CreatePlanHandler)
		r.Post("/nettify/plan", handlers.CreateNettifyPlanHandler)
		r.Get("/ports", handlers.PortsInUseHandler)
		r.Get("/proxies", handlers.GetProxiesHandler)
		r.Post("/restore", handlers.RestoreHandler)
	})

	// Monitoring routes
	r.Get("/monitoring", handlers.MonitoringPanelHandler)
	r.Get("/monitoring/api", handlers.MonitoringAPIHandler)

	log.Println("🌐 Listening on http://0.0.0.0:9090")
	log.Fatal(http.ListenAndServe(":9090", r))
}
