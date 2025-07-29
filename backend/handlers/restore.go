package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"oceanproxy-api/proxy"
)

func RestoreHandler(w http.ResponseWriter, r *http.Request) {
	data, err := os.ReadFile(proxy.LogPath)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to read proxy log: %v", err), http.StatusInternalServerError)
		return
	}

	var entries []proxy.Entry
	if err := json.Unmarshal(data, &entries); err != nil {
		http.Error(w, fmt.Sprintf("Failed to parse proxy log: %v", err), http.StatusInternalServerError)
		return
	}

	existing := make(map[string]map[string]bool)
	for _, e := range entries {
		if existing[e.PlanID] == nil {
			existing[e.PlanID] = make(map[string]bool)
		}
		existing[e.PlanID][e.Subdomain] = true
	}

	var restored, failed []string
	var newEntries []proxy.Entry

	for _, e := range entries {
		if e.ExpiresAt < time.Now().Unix() {
			continue
		}

		err := proxy.Spawn3proxy(e)
		if err != nil {
			failed = append(failed, e.PlanID+"-"+e.Subdomain)
		} else {
			restored = append(restored, e.PlanID+"-"+e.Subdomain)
		}

		// Add missing region (eu/usa) logic
		if e.Subdomain == "eu" && !existing[e.PlanID]["usa"] {
			usaEntry := proxy.NewEntry(e.PlanID, e.Username, e.Password, "pr-us.proxies.fo", 1337, "usa", e.AuthPort, e.ExpiresAt)
			err := proxy.Spawn3proxy(usaEntry)
			if err == nil {
				newEntries = append(newEntries, usaEntry)
				restored = append(restored, e.PlanID+"-usa")
			} else {
				failed = append(failed, e.PlanID+"-usa")
			}
		}

		if e.Subdomain == "usa" && !existing[e.PlanID]["eu"] {
			euEntry := proxy.NewEntry(e.PlanID, e.Username, e.Password, "pr-eu.proxies.fo", 1338, "eu", e.AuthPort, e.ExpiresAt)
			err := proxy.Spawn3proxy(euEntry)
			if err == nil {
				newEntries = append(newEntries, euEntry)
				restored = append(restored, e.PlanID+"-eu")
			} else {
				failed = append(failed, e.PlanID+"-eu")
			}
		}
	}

	if len(newEntries) > 0 {
		entries = append(entries, newEntries...)
		_ = proxy.SaveProxyLog(entries)
	}

	JSON(w, map[string]interface{}{
		"restored": restored,
		"failed":   failed,
	})
}
