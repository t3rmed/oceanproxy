package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/joho/godotenv"
)

var (
	apiKey      string
	apiBaseURL  = "https://app.proxies.fo/api"
	bearerToken string
	baseDomain  string
)

const proxyLogPath = "/var/log/oceanproxy/proxies.json"

type ProxyEntry struct {
	PlanID    string `json:"plan_id"`
	Username  string `json:"username"`
	Password  string `json:"password"`
	AuthHost  string `json:"auth_host"`
	LocalHost string `json:"local_host"`
	AuthPort  int    `json:"auth_port"`
	LocalPort int    `json:"local_port"`
	Subdomain string `json:"subdomain"`
	ExpiresAt int64  `json:"expires_at"`
	CreatedAt int64  `json:"created_at"`
}

func main() {
	log.Println("🚀 Starting OceanProxy API Server...")

	if err := godotenv.Load(); err != nil {
		log.Println("⚠️ No .env file found, using system environment variables")
	}

	apiKey = os.Getenv("API_KEY")
	bearerToken = os.Getenv("BEARER_TOKEN")
	baseDomain = os.Getenv("DOMAIN")

	log.Printf("🔧 Config loaded - API_KEY: %s, BEARER_TOKEN: %s, DOMAIN: %s",
		maskString(apiKey), maskString(bearerToken), baseDomain)

	if apiKey == "" || bearerToken == "" || baseDomain == "" {
		log.Fatal("❌ Missing API_KEY, BEARER_TOKEN or DOMAIN in .env")
	}

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":    "healthy",
			"timestamp": time.Now().Format(time.RFC3339),
		})
	})

	r.Group(func(r chi.Router) {
		r.Use(authMiddleware)
		r.Post("/plan", createPlanHandler)
		r.Get("/proxies", getProxiesHandler)
		r.Post("/restore", restoreHandler)
	})

	log.Println("🌐 Listening on http://0.0.0.0:9090")
	log.Fatal(http.ListenAndServe(":9090", r))
}

func maskString(s string) string {
	if len(s) <= 4 {
		return strings.Repeat("*", len(s))
	}
	return s[:2] + strings.Repeat("*", len(s)-4) + s[len(s)-2:]
}

func authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if token != bearerToken {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func createPlanHandler(w http.ResponseWriter, r *http.Request) {
	log.Println("📋 Creating plan...")

	if err := r.ParseForm(); err != nil {
		http.Error(w, fmt.Sprintf("Invalid form data: %v", err), http.StatusBadRequest)
		return
	}

	reseller := r.FormValue("reseller")
	duration := r.FormValue("duration")
	bandwidth := r.FormValue("bandwidth")
	threads := r.FormValue("threads")

	resellerMap := map[string]string{
		"residential": "7c9ea873-63f9-4013-9147-3807cc6f0553",
		"isp":         "3471aa35-7922-488a-a7a9-b92a5510080e",
		"datacenter":  "b3fd0f3c-693d-4ec5-b49f-c77feaab0b72",
	}

	resellerID, ok := resellerMap[reseller]
	if !ok {
		http.Error(w, "Invalid reseller type", http.StatusBadRequest)
		return
	}

	form := url.Values{}
	form.Set("reseller", resellerID)

	switch reseller {
	case "residential", "isp":
		if bandwidth == "" {
			bandwidth = "1"
		}
		form.Set("bandwidth", bandwidth)
		form.Set("duration", "180")
	case "datacenter":
		if threads == "" {
			threads = "500"
		}
		if duration == "" {
			duration = "1"
		}
		form.Set("threads", threads)
		form.Set("duration", duration)
	}

	req, _ := http.NewRequest("POST", apiBaseURL+"/plans/new", strings.NewReader(form.Encode()))
	req.Header.Set("X-Api-Auth", apiKey)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		http.Error(w, fmt.Sprintf("API request failed: %v", err), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != 200 {
		http.Error(w, fmt.Sprintf("API error: %s", string(body)), resp.StatusCode)
		return
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		http.Error(w, "Failed to parse API response", http.StatusBadGateway)
		return
	}

	data := result["Data"].(map[string]interface{})
	user := data["AuthUsername"].(string)
	pass := data["AuthPassword"].(string)
	planID := data["ID"].(string)
	authPort := int(data["AuthPort"].(float64))
	expires := int64(data["EndsDate"].(float64))

	// Spawn both EU and USA proxies
	regionProxies := []struct {
		UpstreamHost string
		LocalPort    int
		Subdomain    string
	}{
		{"pr-eu.proxies.fo", 1338, "eu"},
		{"pr-us.proxies.fo", 1337, "usa"},
	}

	for _, proxy := range regionProxies {
		err := spawn3proxy(planID, proxy.LocalPort, user, pass, proxy.UpstreamHost, authPort)
		if err != nil {
			http.Error(w, fmt.Sprintf("Failed to spawn proxy for %s: %v", proxy.Subdomain, err), http.StatusInternalServerError)
			return
		}

		logEntry := ProxyEntry{
			PlanID:    planID,
			Username:  user,
			Password:  pass,
			AuthHost:  proxy.UpstreamHost,
			LocalHost: fmt.Sprintf("%s.%s", proxy.Subdomain, baseDomain),
			AuthPort:  authPort,
			LocalPort: proxy.LocalPort,
			Subdomain: proxy.Subdomain,
			ExpiresAt: expires,
			CreatedAt: time.Now().Unix(),
		}

		_ = logProxy(logEntry)
	}

	response := map[string]interface{}{
		"success":    true,
		"plan_id":    planID,
		"username":   user,
		"password":   pass,
		"expires_at": expires,
		"proxies": []string{
			fmt.Sprintf("http://%s:%s@eu.%s:1338", user, pass, baseDomain),
			fmt.Sprintf("http://%s:%s@usa.%s:1337", user, pass, baseDomain),
		},
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(response)
}

func spawn3proxy(plan string, port int, user, pass, upstreamHost string, upstreamPort int) error {
	cmd := exec.Command("bash", "/root/create_proxy_plan.sh", plan, fmt.Sprintf("%d", port), user, pass, upstreamHost, fmt.Sprintf("%d", upstreamPort))
	out, err := cmd.CombinedOutput()
	log.Printf("🛠️  Spawn output: %s", out)
	if err != nil {
		log.Printf("❌ Spawn error: %v", err)
	}
	return err
}

func restoreHandler(w http.ResponseWriter, r *http.Request) {
	log.Println("🔁 Manual restore triggered via /restore")

	data, err := os.ReadFile(proxyLogPath)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to read proxy log: %v", err), http.StatusInternalServerError)
		return
	}

	var entries []ProxyEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		http.Error(w, fmt.Sprintf("Failed to parse proxy log: %v", err), http.StatusInternalServerError)
		return
	}

	existingMap := make(map[string]map[string]bool)
	for _, entry := range entries {
		if _, ok := existingMap[entry.PlanID]; !ok {
			existingMap[entry.PlanID] = make(map[string]bool)
		}
		existingMap[entry.PlanID][entry.Subdomain] = true
	}

	var restored []string
	var failed []string
	var newEntries []ProxyEntry

	for _, entry := range entries {
		if entry.ExpiresAt < time.Now().Unix() {
			continue
		}

		// Always restore existing
		err := spawn3proxy(entry.PlanID, entry.LocalPort, entry.Username, entry.Password, entry.AuthHost, entry.AuthPort)
		if err != nil {
			log.Printf("❌ Failed to restore proxy %s [%s]: %v", entry.PlanID, entry.Subdomain, err)
			failed = append(failed, entry.PlanID+"-"+entry.Subdomain)
		} else {
			restored = append(restored, entry.PlanID+"-"+entry.Subdomain)
		}

		// If it's residential and missing the sibling region, add it
		if entry.Subdomain == "eu" && !existingMap[entry.PlanID]["usa"] {
			log.Printf("➕ Adding missing USA proxy for plan %s", entry.PlanID)
			err := spawn3proxy(entry.PlanID, 1337, entry.Username, entry.Password, "pr-us.proxies.fo", entry.AuthPort)
			if err == nil {
				newEntries = append(newEntries, ProxyEntry{
					PlanID:    entry.PlanID,
					Username:  entry.Username,
					Password:  entry.Password,
					AuthHost:  "pr-us.proxies.fo",
					LocalHost: "usa." + baseDomain,
					AuthPort:  entry.AuthPort,
					LocalPort: 1337,
					Subdomain: "usa",
					ExpiresAt: entry.ExpiresAt,
					CreatedAt: entry.CreatedAt,
				})
				restored = append(restored, entry.PlanID+"-usa")
			}
		} else if entry.Subdomain == "usa" && !existingMap[entry.PlanID]["eu"] {
			log.Printf("➕ Adding missing EU proxy for plan %s", entry.PlanID)
			err := spawn3proxy(entry.PlanID, 1338, entry.Username, entry.Password, "pr-eu.proxies.fo", entry.AuthPort)
			if err == nil {
				newEntries = append(newEntries, ProxyEntry{
					PlanID:    entry.PlanID,
					Username:  entry.Username,
					Password:  entry.Password,
					AuthHost:  "pr-eu.proxies.fo",
					LocalHost: "eu." + baseDomain,
					AuthPort:  entry.AuthPort,
					LocalPort: 1338,
					Subdomain: "eu",
					ExpiresAt: entry.ExpiresAt,
					CreatedAt: entry.CreatedAt,
				})
				restored = append(restored, entry.PlanID+"-eu")
			}
		}
	}

	if len(newEntries) > 0 {
		entries = append(entries, newEntries...)
		_ = saveProxyLog(entries)
	}

	resp := map[string]interface{}{
		"restored": restored,
		"failed":   failed,
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func saveProxyLog(entries []ProxyEntry) error {
	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		return err
	}
	_ = os.MkdirAll("/var/log/oceanproxy", 0755)
	return os.WriteFile(proxyLogPath, data, 0644)
}

func getProxiesHandler(w http.ResponseWriter, r *http.Request) {
	data, err := os.ReadFile(proxyLogPath)
	if err != nil {
		http.Error(w, "Read error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(data)
}

func logProxy(entry ProxyEntry) error {
	var entries []ProxyEntry
	if data, err := os.ReadFile(proxyLogPath); err == nil {
		_ = json.Unmarshal(data, &entries)
	}
	entries = append(entries, entry)
	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		return err
	}
	_ = os.MkdirAll("/var/log/oceanproxy", 0755)
	return os.WriteFile(proxyLogPath, data, 0644)
}
