package handlers

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/url"
	"oceanproxy-api/config"
	"oceanproxy-api/providers"
	"oceanproxy-api/proxy"
	"os"
)

// GetNettifyPlansHandler lists all Nettify plans and spawns any non-expired plans not present locally
func GetNettifyPlansHandler(w http.ResponseWriter, r *http.Request) {
	plans, err := providers.RetreiveAllPlans()
	if err != nil {
		http.Error(w, "Failed to fetch Nettify plans: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Load local proxies from log
	localProxies := make(map[string]bool)
	logPath := proxy.LogPath
	if data, err := os.ReadFile(logPath); err == nil {
		var entries []proxy.Entry
		if err := json.Unmarshal(data, &entries); err == nil {
			for _, entry := range entries {
				localProxies[entry.PlanID] = true
			}
		}
	}

	spawned := []string{}
	for _, plan := range plans {
		if !plan.Active || !plan.Enabled {
			continue // skip expired/disabled
		}
		if _, exists := localProxies[plan.PlanID]; exists {
			continue // already exists
		}
		// Generate a secure random password
		newPass := generateSecurePassword(16)
		// Set the new password via Nettify API
		putURL := "https://api.nettify.xyz/plans/" + plan.PlanID
		putBody := map[string]string{"new_password": newPass}
		putBodyJSON, _ := json.Marshal(putBody)
		putReq, _ := http.NewRequest("PUT", putURL, bytes.NewBuffer(putBodyJSON))
		putReq.Header.Set("Authorization", "Bearer "+config.NettifyAPIKey)
		putReq.Header.Set("Content-Type", "application/json")
		putResp, err := http.DefaultClient.Do(putReq)
		if err != nil || putResp.StatusCode != 200 {
			continue // skip if failed to set password
		}
		putResp.Body.Close()
		// Now spawn the proxy with the new password
		form := make(map[string][]string)
		form["plan_type"] = []string{plan.PlanType}
		form["username"] = []string{plan.Username}
		form["password"] = []string{newPass}
		_, err = providers.CreateNettifyPlan(urlValuesFromMap(form))
		if err == nil {
			spawned = append(spawned, plan.PlanID)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"plans":   plans,
		"spawned": spawned,
	})
}

// Helper to convert map[string][]string to url.Values
func urlValuesFromMap(m map[string][]string) url.Values {
	v := url.Values{}
	for key, vals := range m {
		for _, val := range vals {
			v.Add(key, val)
		}
	}
	return v
}

// Helper to generate a secure random password
func generateSecurePassword(length int) string {
	b := make([]byte, length)
	_, err := rand.Read(b)
	if err != nil {
		return "changeme123!" // fallback
	}
	return base64.RawURLEncoding.EncodeToString(b)[:length]
}
